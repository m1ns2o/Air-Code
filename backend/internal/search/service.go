package search

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/air-code/air-code/backend/internal/project"
)

const (
	defaultLimit = 100
	maxLimit     = 500
	maxFileBytes = 2 * 1024 * 1024
)

type Request struct {
	Query         string `json:"query"`
	Path          string `json:"path"`
	Limit         int    `json:"limit"`
	CaseSensitive bool   `json:"caseSensitive"`
}

type Response struct {
	Query     string   `json:"query"`
	Results   []Result `json:"results"`
	Truncated bool     `json:"truncated"`
}

type Result struct {
	Path   string `json:"path"`
	Line   int    `json:"lineNumber"`
	Column int    `json:"column"`
	Text   string `json:"line"`
}

type Service struct {
	rgPath string
}

func NewService() *Service {
	rgPath, _ := exec.LookPath("rg")
	return &Service{rgPath: rgPath}
}

func NewFallbackServiceForTest() *Service {
	return &Service{}
}

func (s *Service) Search(ctx context.Context, p *project.Project, req Request) (Response, error) {
	req.Query = strings.TrimSpace(req.Query)
	if req.Query == "" {
		return Response{}, errors.New("query is required")
	}
	if req.Path == "" {
		req.Path = "."
	}
	if _, err := project.ResolveUnder(p.Root, req.Path); err != nil {
		return Response{}, err
	}
	req.Limit = normalizeLimit(req.Limit)
	if s.rgPath != "" {
		resp, err := s.searchWithRipgrep(ctx, p, req)
		if err == nil {
			return resp, nil
		}
	}
	return searchWithGo(p, req)
}

func (s *Service) searchWithRipgrep(ctx context.Context, p *project.Project, req Request) (Response, error) {
	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	args := []string{
		"--json",
		"--line-number",
		"--column",
		"--with-filename",
		"--hidden",
		"--glob", "!.git",
		"--glob", "!.git/**",
		"--glob", "!.aircode",
		"--glob", "!.aircode/**",
		"--glob", "!node_modules",
		"--glob", "!node_modules/**",
		"--glob", "!vendor",
		"--glob", "!vendor/**",
	}
	if !req.CaseSensitive {
		args = append(args, "--ignore-case")
	}
	for _, ignore := range p.Ignore {
		ignore = strings.TrimSpace(ignore)
		if ignore == "" {
			continue
		}
		args = append(args, "--glob", "!"+ignore, "--glob", "!"+strings.TrimSuffix(ignore, "/")+"/**")
	}
	args = append(args, "--", req.Query, req.Path)
	cmd := exec.CommandContext(ctx, s.rgPath, args...)
	cmd.Dir = p.Root
	output, err := cmd.Output()
	if err != nil {
		if exit, ok := err.(*exec.ExitError); ok && exit.ExitCode() == 1 {
			return Response{Query: req.Query, Results: []Result{}}, nil
		}
		return Response{}, err
	}
	return parseRipgrepJSON(req.Query, output, req.Limit)
}

type rgEvent struct {
	Type string `json:"type"`
	Data struct {
		Path struct {
			Text string `json:"text"`
		} `json:"path"`
		Lines struct {
			Text string `json:"text"`
		} `json:"lines"`
		LineNumber int `json:"line_number"`
		Submatches []struct {
			Start int `json:"start"`
		} `json:"submatches"`
	} `json:"data"`
}

func parseRipgrepJSON(query string, output []byte, limit int) (Response, error) {
	response := Response{Query: query, Results: []Result{}}
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		var event rgEvent
		if err := json.Unmarshal(scanner.Bytes(), &event); err != nil {
			return Response{}, err
		}
		if event.Type != "match" {
			continue
		}
		if len(response.Results) >= limit {
			response.Truncated = true
			continue
		}
		column := 1
		if len(event.Data.Submatches) > 0 {
			column = event.Data.Submatches[0].Start + 1
		}
		response.Results = append(response.Results, Result{
			Path:   normalizeRelPath(event.Data.Path.Text),
			Line:   event.Data.LineNumber,
			Column: column,
			Text:   strings.TrimRight(event.Data.Lines.Text, "\r\n"),
		})
	}
	if err := scanner.Err(); err != nil {
		return Response{}, err
	}
	return response, nil
}

func normalizeRelPath(path string) string {
	path = filepath.ToSlash(path)
	path = strings.TrimPrefix(path, "./")
	if path == "" {
		return "."
	}
	return path
}

func searchWithGo(p *project.Project, req Request) (Response, error) {
	start, err := project.ResolveUnder(p.Root, req.Path)
	if err != nil {
		return Response{}, err
	}
	root, err := project.ResolveUnder(p.Root, ".")
	if err != nil {
		return Response{}, err
	}
	response := Response{Query: req.Query, Results: []Result{}}
	needle := req.Query
	if !req.CaseSensitive {
		needle = strings.ToLower(needle)
	}
	err = filepath.WalkDir(start, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return nil
		}
		if shouldIgnore(path, entry, root, p.Ignore) {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if entry.IsDir() {
			return nil
		}
		if len(response.Results) >= req.Limit {
			response.Truncated = true
			return filepath.SkipAll
		}
		results, err := searchFile(root, path, needle, req.CaseSensitive, req.Limit-len(response.Results))
		if err != nil {
			return nil
		}
		response.Results = append(response.Results, results...)
		if len(response.Results) >= req.Limit {
			response.Truncated = true
			return filepath.SkipAll
		}
		return nil
	})
	if err != nil {
		return Response{}, err
	}
	sort.Slice(response.Results, func(i, j int) bool {
		if response.Results[i].Path != response.Results[j].Path {
			return response.Results[i].Path < response.Results[j].Path
		}
		return response.Results[i].Line < response.Results[j].Line
	})
	return response, nil
}

func searchFile(root, path, needle string, caseSensitive bool, limit int) ([]Result, error) {
	info, err := os.Stat(path)
	if err != nil || info.Size() > maxFileBytes {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if err != nil || bytes.IndexByte(data, 0) >= 0 {
		return nil, err
	}
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return nil, err
	}
	var results []Result
	lines := strings.Split(string(data), "\n")
	for index, line := range lines {
		haystack := line
		if !caseSensitive {
			haystack = strings.ToLower(haystack)
		}
		column := strings.Index(haystack, needle)
		if column < 0 {
			continue
		}
		results = append(results, Result{
			Path:   filepath.ToSlash(rel),
			Line:   index + 1,
			Column: column + 1,
			Text:   strings.TrimRight(line, "\r"),
		})
		if len(results) >= limit {
			break
		}
	}
	return results, nil
}

func shouldIgnore(path string, entry fs.DirEntry, root string, ignores []string) bool {
	name := entry.Name()
	if name == ".git" || name == ".aircode" || name == "node_modules" || name == "vendor" {
		return true
	}
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return true
	}
	rel = filepath.ToSlash(rel)
	for _, ignore := range ignores {
		ignore = strings.Trim(strings.TrimSpace(ignore), "/")
		if ignore == "" {
			continue
		}
		if ignore == name || ignore == rel {
			return true
		}
		if ok, _ := filepath.Match(ignore, name); ok {
			return true
		}
		if ok, _ := filepath.Match(ignore, rel); ok {
			return true
		}
		if strings.HasPrefix(rel, ignore+"/") {
			return true
		}
	}
	return false
}

func normalizeLimit(limit int) int {
	if limit <= 0 {
		return defaultLimit
	}
	if limit > maxLimit {
		return maxLimit
	}
	return limit
}

func (r Result) String() string {
	return fmt.Sprintf("%s:%d:%d:%s", r.Path, r.Line, r.Column, r.Text)
}
