package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type CatalogItem struct {
	ID             string   `json:"id"`
	Name           string   `json:"name"`
	DisplayName    string   `json:"displayName"`
	Description    string   `json:"description"`
	Source         string   `json:"source"`
	PackageType    string   `json:"packageType,omitempty"`
	InstallCommand string   `json:"installCommand,omitempty"`
	Command        string   `json:"command,omitempty"`
	Args           []string `json:"args,omitempty"`
	RemoteURL      string   `json:"remoteUrl,omitempty"`
	RequiresEnv    []string `json:"requiresEnv,omitempty"`
	Homepage       string   `json:"homepage,omitempty"`
	Repository     string   `json:"repository,omitempty"`
	Verified       bool     `json:"verified"`
	LastUpdated    string   `json:"lastUpdated,omitempty"`
}

type CatalogSearchResponse struct {
	Items []CatalogItem `json:"items"`
}

type CatalogClient struct {
	HTTP *http.Client
}

func (c CatalogClient) Search(ctx context.Context, source, query string) (CatalogSearchResponse, error) {
	source = normalizeCatalogSource(source)
	query = strings.TrimSpace(query)
	if query == "" {
		query = "github"
	}
	switch source {
	case "smithery":
		return c.searchSmithery(ctx, query)
	case "glama":
		return c.searchGlama(ctx, query)
	default:
		return c.searchOfficial(ctx, query)
	}
}

func (c CatalogClient) Item(ctx context.Context, source, id string) (CatalogItem, error) {
	id = strings.TrimSpace(id)
	if id == "" {
		return CatalogItem{}, fmt.Errorf("catalog item id is required")
	}
	response, err := c.Search(ctx, source, id)
	if err != nil {
		return CatalogItem{}, err
	}
	for _, item := range response.Items {
		if item.ID == id || item.Name == id {
			return item, nil
		}
	}
	if len(response.Items) > 0 {
		return response.Items[0], nil
	}
	return CatalogItem{}, fmt.Errorf("catalog item %q not found", id)
}

func (c CatalogClient) httpClient() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return &http.Client{Timeout: 8 * time.Second}
}

func normalizeCatalogSource(source string) string {
	switch strings.ToLower(strings.TrimSpace(source)) {
	case "smithery", "glama", "official":
		return strings.ToLower(strings.TrimSpace(source))
	default:
		return "official"
	}
}

func (c CatalogClient) searchOfficial(ctx context.Context, query string) (CatalogSearchResponse, error) {
	endpoint := "https://registry.modelcontextprotocol.io/v0.1/servers?limit=20&search=" + url.QueryEscape(query)
	var payload struct {
		Servers []struct {
			Server struct {
				Name        string `json:"name"`
				Title       string `json:"title"`
				Description string `json:"description"`
				Version     string `json:"version"`
				Repository  *struct {
					URL string `json:"url"`
				} `json:"repository"`
				Remotes []struct {
					Type string `json:"type"`
					URL  string `json:"url"`
				} `json:"remotes"`
				Packages []struct {
					RegistryName string   `json:"registry_name"`
					Name         string   `json:"name"`
					PackageArgs  []string `json:"package_arguments"`
				} `json:"packages"`
			} `json:"server"`
			Meta map[string]struct {
				Status    string `json:"status"`
				UpdatedAt string `json:"updatedAt"`
				IsLatest  bool   `json:"isLatest"`
			} `json:"_meta"`
		} `json:"servers"`
	}
	if err := c.getJSON(ctx, endpoint, &payload); err != nil {
		return CatalogSearchResponse{Items: fallbackCatalog(query, "official")}, nil
	}
	var items []CatalogItem
	for _, entry := range payload.Servers {
		server := entry.Server
		if server.Name == "" {
			continue
		}
		item := CatalogItem{
			ID:          server.Name,
			Name:        shortCatalogName(server.Name),
			DisplayName: firstNonEmpty(server.Title, shortCatalogName(server.Name)),
			Description: server.Description,
			Source:      "official",
			Verified:    true,
		}
		if server.Repository != nil {
			item.Repository = server.Repository.URL
			item.Homepage = server.Repository.URL
		}
		for _, remote := range server.Remotes {
			if remote.URL != "" {
				item.PackageType = remote.Type
				item.RemoteURL = remote.URL
				item.InstallCommand = "remote " + remote.URL
				break
			}
		}
		for _, pkg := range server.Packages {
			if item.RemoteURL == "" && pkg.Name != "" {
				item.PackageType = pkg.RegistryName
				item.Command, item.Args = packageCommand(pkg.RegistryName, pkg.Name, pkg.PackageArgs)
				item.InstallCommand = strings.Join(append([]string{item.Command}, item.Args...), " ")
				break
			}
		}
		for _, meta := range entry.Meta {
			item.LastUpdated = meta.UpdatedAt
			if !meta.IsLatest {
				item.Verified = false
			}
			break
		}
		items = append(items, item)
	}
	if len(items) == 0 {
		items = fallbackCatalog(query, "official")
	}
	return CatalogSearchResponse{Items: items}, nil
}

func (c CatalogClient) searchSmithery(ctx context.Context, query string) (CatalogSearchResponse, error) {
	endpoint := "https://api.smithery.ai/servers?q=" + url.QueryEscape(query) + "&pageSize=20"
	var payload struct {
		Servers []struct {
			ID            string `json:"id"`
			QualifiedName string `json:"qualifiedName"`
			DisplayName   string `json:"displayName"`
			Description   string `json:"description"`
			Verified      bool   `json:"verified"`
			Remote        bool   `json:"remote"`
			Homepage      string `json:"homepage"`
			CreatedAt     string `json:"createdAt"`
		} `json:"servers"`
	}
	if err := c.getJSON(ctx, endpoint, &payload); err != nil {
		return CatalogSearchResponse{Items: fallbackCatalog(query, "smithery")}, nil
	}
	items := make([]CatalogItem, 0, len(payload.Servers))
	for _, server := range payload.Servers {
		name := firstNonEmpty(server.QualifiedName, server.ID)
		item := CatalogItem{
			ID:             name,
			Name:           shortCatalogName(name),
			DisplayName:    firstNonEmpty(server.DisplayName, shortCatalogName(name)),
			Description:    server.Description,
			Source:         "smithery",
			Homepage:       server.Homepage,
			Verified:       server.Verified,
			LastUpdated:    server.CreatedAt,
			PackageType:    "smithery",
			InstallCommand: "smithery add " + name,
		}
		if server.Remote {
			item.RemoteURL = "https://server.smithery.ai/" + strings.TrimPrefix(name, "@") + "/mcp"
			item.InstallCommand = "remote " + item.RemoteURL
		}
		items = append(items, item)
	}
	if len(items) == 0 {
		items = fallbackCatalog(query, "smithery")
	}
	return CatalogSearchResponse{Items: items}, nil
}

func (c CatalogClient) searchGlama(ctx context.Context, query string) (CatalogSearchResponse, error) {
	endpoint := "https://glama.ai/api/mcp/v1/servers?limit=20&query=" + url.QueryEscape(query)
	var payload struct {
		Servers []struct {
			ID          string `json:"id"`
			Name        string `json:"name"`
			Namespace   string `json:"namespace"`
			Slug        string `json:"slug"`
			Description string `json:"description"`
			URL         string `json:"url"`
			Repository  *struct {
				URL string `json:"url"`
			} `json:"repository"`
			Env struct {
				Required []string `json:"required"`
			} `json:"environmentVariablesJsonSchema"`
		} `json:"servers"`
	}
	if err := c.getJSON(ctx, endpoint, &payload); err != nil {
		return CatalogSearchResponse{Items: fallbackCatalog(query, "glama")}, nil
	}
	items := make([]CatalogItem, 0, len(payload.Servers))
	for _, server := range payload.Servers {
		name := firstNonEmpty(server.Name, server.Slug, server.ID)
		item := CatalogItem{
			ID:             server.ID,
			Name:           shortCatalogName(name),
			DisplayName:    name,
			Description:    server.Description,
			Source:         "glama",
			Homepage:       server.URL,
			PackageType:    "glama",
			InstallCommand: "inspect on Glama",
			RequiresEnv:    server.Env.Required,
		}
		if server.Repository != nil {
			item.Repository = server.Repository.URL
		}
		items = append(items, item)
	}
	if len(items) == 0 {
		items = fallbackCatalog(query, "glama")
	}
	return CatalogSearchResponse{Items: items}, nil
}

func (c CatalogClient) getJSON(ctx context.Context, endpoint string, out interface{}) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/json")
	resp, err := c.httpClient().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("catalog HTTP %d", resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func packageCommand(registry, name string, args []string) (string, []string) {
	switch strings.ToLower(registry) {
	case "npm":
		return "npx", append([]string{"-y", name}, args...)
	case "pypi":
		return "uvx", append([]string{name}, args...)
	default:
		return name, args
	}
}

func fallbackCatalog(query, source string) []CatalogItem {
	items := []CatalogItem{
		{ID: "github", Name: "github", DisplayName: "GitHub", Description: "Repository, issues, pull request, and workflow MCP server.", Source: source, PackageType: "remote", RemoteURL: "https://api.githubcopilot.com/mcp/", InstallCommand: "remote https://api.githubcopilot.com/mcp/", Verified: true},
		{ID: "filesystem", Name: "filesystem", DisplayName: "Filesystem", Description: "Local filesystem MCP server. Configure allowed folders before installing.", Source: source, PackageType: "npm", Command: "npx", Args: []string{"-y", "@modelcontextprotocol/server-filesystem"}, InstallCommand: "npx -y @modelcontextprotocol/server-filesystem", Verified: true},
		{ID: "fetch", Name: "fetch", DisplayName: "Fetch", Description: "Fetch web pages and convert them into model-friendly text.", Source: source, PackageType: "pypi", Command: "uvx", Args: []string{"mcp-server-fetch"}, InstallCommand: "uvx mcp-server-fetch", Verified: true},
	}
	query = strings.ToLower(strings.TrimSpace(query))
	if query == "" {
		return items
	}
	var filtered []CatalogItem
	for _, item := range items {
		haystack := strings.ToLower(item.Name + " " + item.DisplayName + " " + item.Description)
		if strings.Contains(haystack, query) {
			filtered = append(filtered, item)
		}
	}
	if len(filtered) == 0 {
		return items
	}
	return filtered
}

func shortCatalogName(value string) string {
	value = strings.Trim(value, "/")
	if value == "" {
		return "mcp"
	}
	parts := strings.FieldsFunc(value, func(r rune) bool { return r == '/' || r == '@' })
	if len(parts) == 0 {
		return value
	}
	return parts[len(parts)-1]
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}
