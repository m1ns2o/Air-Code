package setup

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/air-code/air-code/backend/internal/config"
)

type Options struct {
	ConfigPath        string
	AgentIDs          []string
	LanguageServerIDs []string
	Yes               bool
	CheckOnly         bool
	SkipUpdates       bool
	In                io.Reader
	Out               io.Writer
}

type DoctorOptions struct {
	Update bool
	Yes    bool
	In     io.Reader
	Out    io.Writer
}

type UpdateState string

const (
	UpdateNotChecked UpdateState = "not-checked"
	UpdateAvailable  UpdateState = "available"
	UpdateCurrent    UpdateState = "current"
	UpdateFailed     UpdateState = "failed"
	UpdateUnknown    UpdateState = "unknown"
)

type UpdateStatus struct {
	State   UpdateState
	Summary string
	Raw     string
	Err     error
}

func Run(cfg config.Config, opts Options) (config.Config, error) {
	if opts.In == nil {
		opts.In = strings.NewReader("")
	}
	if opts.Out == nil {
		opts.Out = io.Discard
	}
	reader := bufio.NewReader(opts.In)
	if cfg.Agents == nil {
		cfg.Agents = map[string]config.AgentCmd{}
	}
	if cfg.LanguageServers == nil {
		cfg.LanguageServers = map[string]config.LanguageServerCmd{}
	}
	fmt.Fprintf(opts.Out, "Air Code setup\n%s\n\n", PlatformNote())
	printCapabilities(opts.Out, cfg)

	ids := opts.AgentIDs
	if len(ids) == 0 && !opts.CheckOnly {
		fmt.Fprint(opts.Out, "\nSelect agents to install/configure (comma separated, default codex): ")
		line, _ := reader.ReadString('\n')
		ids = splitIDs(line)
		if len(ids) == 0 {
			ids = []string{"codex"}
		}
	}
	ids, skipAgents := normalizeSetupIDs(ids)
	if !skipAgents {
		for _, id := range ids {
			recipe, ok := RecipeByID(id)
			if !ok {
				return cfg, fmt.Errorf("unknown agent %q", id)
			}
			if err := configureRecipe(&cfg, recipe, opts, reader); err != nil {
				return cfg, err
			}
		}
	}
	languageServerIDs := opts.LanguageServerIDs
	if len(languageServerIDs) == 0 && !opts.CheckOnly {
		defaultLanguageServers := strings.Join(DefaultLanguageServerIDs(), ",")
		fmt.Fprintf(opts.Out, "\nSelect language intelligence servers to install/configure (comma separated, default %s; use none to skip): ", defaultLanguageServers)
		line, err := reader.ReadString('\n')
		languageServerIDs = splitIDs(line)
		if len(languageServerIDs) == 0 {
			languageServerIDs = DefaultLanguageServerIDs()
		}
		_ = err
	}
	languageServerIDs, skipLanguageServers := normalizeSetupIDs(languageServerIDs)
	if !skipLanguageServers {
		for _, id := range languageServerIDs {
			recipe, ok := LanguageServerRecipeByID(id)
			if !ok {
				return cfg, fmt.Errorf("unknown language server %q", id)
			}
			if err := configureLanguageServerRecipe(&cfg, recipe, opts, reader); err != nil {
				return cfg, err
			}
		}
	}
	if opts.ConfigPath != "" && !opts.CheckOnly {
		if err := config.Save(opts.ConfigPath, cfg); err != nil {
			return cfg, err
		}
		fmt.Fprintf(opts.Out, "\nUpdated %s\n", opts.ConfigPath)
	}
	return cfg, nil
}

func Doctor(cfg config.Config, opts DoctorOptions) error {
	if opts.In == nil {
		opts.In = strings.NewReader("")
	}
	if opts.Out == nil {
		opts.Out = io.Discard
	}
	reader := bufio.NewReader(opts.In)
	fmt.Fprintf(opts.Out, "Air Code doctor\n%s\n\n", PlatformNote())
	printCapabilities(opts.Out, cfg)
	return doctorUpdates(cfg, opts, reader)
}

func printCapabilities(out io.Writer, cfg config.Config) {
	fmt.Fprintln(out, "Agents:")
	for _, cap := range CapabilityList(cfg.Agents) {
		state := cap.InstallStatus
		if cap.Configured {
			state = "ready"
		}
		fmt.Fprintf(out, "- %-10s %-10s command=%s\n", cap.ID, state, cap.Command)
	}
	fmt.Fprintln(out, "\nLanguage intelligence:")
	for _, cap := range LanguageServerCapabilityList(cfg.LanguageServers) {
		state := cap.InstallStatus
		if cap.Configured {
			state = "ready"
		}
		fmt.Fprintf(out, "- %-10s %-10s command=%s\n", cap.ID, state, cap.Command)
	}
}

func configureRecipe(cfg *config.Config, recipe Recipe, opts Options, reader *bufio.Reader) error {
	resolvedCommand, installed := resolveCommandPath(recipe.Command)
	if !installed && !opts.CheckOnly {
		if !opts.Yes {
			fmt.Fprintf(opts.Out, "\n%s install commands:\n", recipe.DisplayName)
			for index, install := range recipe.InstallCommands {
				fmt.Fprintf(opts.Out, "  %d. %s\n", index+1, strings.Join(install, " "))
			}
			fmt.Fprint(opts.Out, "Run these installer commands until one succeeds? [y/N]: ")
			line, _ := reader.ReadString('\n')
			if strings.ToLower(strings.TrimSpace(line)) != "y" {
				cfg.Agents[recipe.ID] = markAgent(recipe.DefaultAgent, "skipped")
				return nil
			}
		}
		if err := runInstallCommands(opts.Out, recipe.InstallCommands); err != nil {
			cfg.Agents[recipe.ID] = markAgent(recipe.DefaultAgent, "failed")
			return err
		}
		resolvedCommand, installed = resolveCommandPath(recipe.Command)
	}
	status := "configured"
	if !installed {
		status = "missing"
	} else {
		for _, verify := range recipe.VerifyCommands {
			if err := runCommand(opts.Out, withResolvedCommand(verify, recipe.Command, resolvedCommand)); err != nil {
				status = "verify-failed"
				break
			}
		}
	}
	agent := recipe.DefaultAgent
	if status == "configured" && resolvedCommand != "" {
		agent.Command = resolvedCommand
	}
	cfg.Agents[recipe.ID] = markAgent(agent, status)
	if recipe.ID == "codex" && status == "configured" && !opts.CheckOnly {
		configureCodexGoals(opts.Out)
	}
	if recipe.ID == "hermes" && status == "configured" && !opts.CheckOnly {
		if err := maybeUpdateRecipe(opts.Out, recipe, resolvedCommand, updatePrompt{
			Yes:         opts.Yes,
			SkipUpdates: opts.SkipUpdates,
			AllowUpdate: true,
			Reader:      reader,
			FailOnError: false,
		}); err != nil {
			return err
		}
		configureHermesCodexRuntime(opts.Out, resolvedCommand)
		fmt.Fprintf(opts.Out, "Hermes is installed at %s. Run `hermes model` or `hermes setup` to configure non-Codex provider credentials.\n", resolvedCommand)
	} else if status == "configured" && opts.CheckOnly {
		_ = reportRecipeUpdate(opts.Out, recipe, resolvedCommand)
	}
	return nil
}

func configureLanguageServerRecipe(cfg *config.Config, recipe LanguageServerRecipe, opts Options, reader *bufio.Reader) error {
	if cfg.LanguageServers == nil {
		cfg.LanguageServers = map[string]config.LanguageServerCmd{}
	}
	resolvedCommand, installed := resolveCommandPath(recipe.Command)
	if !installed && !opts.CheckOnly {
		if !opts.Yes {
			fmt.Fprintf(opts.Out, "\n%s language intelligence install commands:\n", recipe.DisplayName)
			for index, install := range recipe.InstallCommands {
				fmt.Fprintf(opts.Out, "  %d. %s\n", index+1, strings.Join(install, " "))
			}
			fmt.Fprint(opts.Out, "Run these installer commands until one succeeds? [y/N]: ")
			line, _ := reader.ReadString('\n')
			if strings.ToLower(strings.TrimSpace(line)) != "y" {
				cfg.LanguageServers[recipe.ID] = markLanguageServer(recipe.DefaultConfig, "skipped")
				return nil
			}
		}
		if err := runInstallCommands(opts.Out, recipe.InstallCommands); err != nil {
			cfg.LanguageServers[recipe.ID] = markLanguageServer(recipe.DefaultConfig, "failed")
			return err
		}
		resolvedCommand, installed = resolveCommandPath(recipe.Command)
	}
	status := "configured"
	if !installed {
		status = "missing"
	} else {
		for _, verify := range recipe.VerifyCommands {
			if err := runCommand(opts.Out, withResolvedCommand(verify, recipe.Command, resolvedCommand)); err != nil {
				status = "verify-failed"
				break
			}
		}
	}
	server := recipe.DefaultConfig
	if status == "configured" && resolvedCommand != "" {
		server.Command = resolvedCommand
	}
	cfg.LanguageServers[recipe.ID] = markLanguageServer(server, status)
	return nil
}

type updatePrompt struct {
	Yes         bool
	SkipUpdates bool
	AllowUpdate bool
	Reader      *bufio.Reader
	FailOnError bool
}

func doctorUpdates(cfg config.Config, opts DoctorOptions, reader *bufio.Reader) error {
	for _, recipe := range Recipes() {
		if len(recipe.UpdateCheck) == 0 {
			continue
		}
		command := recipe.Command
		if cfgAgent := cfg.Agents[recipe.ID]; strings.TrimSpace(cfgAgent.Command) != "" {
			command = cfgAgent.Command
		}
		resolvedCommand, installed := resolveCommandPath(command)
		if !installed {
			continue
		}
		if err := maybeUpdateRecipe(opts.Out, recipe, resolvedCommand, updatePrompt{
			Yes:         opts.Yes,
			AllowUpdate: opts.Update,
			Reader:      reader,
			FailOnError: opts.Update,
		}); err != nil {
			return err
		}
	}
	return nil
}

func maybeUpdateRecipe(out io.Writer, recipe Recipe, resolvedCommand string, prompt updatePrompt) error {
	if prompt.SkipUpdates {
		return nil
	}
	status := reportRecipeUpdate(out, recipe, resolvedCommand)
	if status.State != UpdateAvailable || !prompt.AllowUpdate {
		return nil
	}
	shouldUpdate := prompt.Yes
	if !shouldUpdate {
		if prompt.Reader == nil {
			prompt.Reader = bufio.NewReader(strings.NewReader(""))
		}
		fmt.Fprintf(out, "Update %s now? [y/N]: ", recipe.DisplayName)
		line, _ := prompt.Reader.ReadString('\n')
		shouldUpdate = strings.EqualFold(strings.TrimSpace(line), "y")
	}
	if !shouldUpdate {
		fmt.Fprintf(out, "%s update skipped.\n", recipe.DisplayName)
		return nil
	}
	if err := runRecipeUpdate(out, recipe, resolvedCommand); err != nil {
		if prompt.FailOnError {
			return err
		}
		fmt.Fprintf(out, "warning: %s update failed: %v\n", recipe.DisplayName, err)
	}
	return nil
}

func reportRecipeUpdate(out io.Writer, recipe Recipe, resolvedCommand string) UpdateStatus {
	status := checkRecipeUpdate(recipe, resolvedCommand)
	if status.State == UpdateNotChecked {
		return status
	}
	fmt.Fprintf(out, "%s update: %s\n", recipe.DisplayName, status.Summary)
	return status
}

func checkRecipeUpdate(recipe Recipe, resolvedCommand string) UpdateStatus {
	if len(recipe.UpdateCheck) == 0 {
		return UpdateStatus{State: UpdateNotChecked}
	}
	var last UpdateStatus
	for _, check := range recipe.UpdateCheck {
		output, err := runCommandCapture(withResolvedCommand(check, recipe.Command, resolvedCommand))
		status := ParseUpdateStatus(output, err)
		if status.State == UpdateAvailable || status.State == UpdateCurrent {
			return status
		}
		last = status
	}
	if last.State == "" {
		return UpdateStatus{State: UpdateUnknown, Summary: "update status unknown"}
	}
	return last
}

func runRecipeUpdate(out io.Writer, recipe Recipe, resolvedCommand string) error {
	if len(recipe.UpdateCommands) == 0 {
		return fmt.Errorf("%s does not define an update command", recipe.DisplayName)
	}
	return runInstallCommands(out, replaceCommands(recipe.UpdateCommands, recipe.Command, resolvedCommand))
}

func replaceCommands(commands [][]string, expectedCommand string, resolvedCommand string) [][]string {
	replaced := make([][]string, 0, len(commands))
	for _, command := range commands {
		replaced = append(replaced, withResolvedCommand(command, expectedCommand, resolvedCommand))
	}
	return replaced
}

func ParseUpdateStatus(output string, err error) UpdateStatus {
	raw := strings.TrimSpace(output)
	lower := strings.ToLower(raw)
	status := UpdateStatus{Raw: raw, Err: err}
	switch {
	case err != nil:
		status.State = UpdateFailed
		status.Summary = firstNonEmptyLine(raw)
		if status.Summary == "" {
			status.Summary = err.Error()
		}
	case strings.Contains(lower, "up to date") ||
		strings.Contains(lower, "up-to-date") ||
		strings.Contains(lower, "already current") ||
		strings.Contains(lower, "already latest") ||
		strings.Contains(lower, "no update"):
		status.State = UpdateCurrent
		status.Summary = firstMatchingLine(raw, "up to date", "up-to-date", "already current", "already latest", "no update")
		if status.Summary == "" {
			status.Summary = "current"
		}
	case strings.Contains(lower, "update available") ||
		strings.Contains(lower, "updates available") ||
		strings.Contains(lower, "commits behind") ||
		strings.Contains(lower, "run 'hermes update'") ||
		strings.Contains(lower, "run `hermes update`"):
		status.State = UpdateAvailable
		status.Summary = firstMatchingLine(raw, "update available", "updates available", "commits behind", "run 'hermes update'", "run `hermes update`")
		if status.Summary == "" {
			status.Summary = "update available"
		}
	default:
		status.State = UpdateUnknown
		status.Summary = firstNonEmptyLine(raw)
		if status.Summary == "" {
			status.Summary = "update status unknown"
		}
	}
	return status
}

func firstNonEmptyLine(value string) string {
	for _, line := range strings.Split(value, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			return line
		}
	}
	return ""
}

func firstMatchingLine(value string, patterns ...string) string {
	for _, line := range strings.Split(value, "\n") {
		trimmed := strings.TrimSpace(line)
		lower := strings.ToLower(trimmed)
		for _, pattern := range patterns {
			if strings.Contains(lower, strings.ToLower(pattern)) {
				return trimmed
			}
		}
	}
	return firstNonEmptyLine(value)
}

func configureHermesCodexRuntime(out io.Writer, command string) {
	if strings.TrimSpace(command) == "" {
		return
	}
	err := runCommand(out, []string{command, "config", "set", "model.openai_runtime", "codex_app_server"})
	if err != nil {
		fmt.Fprintf(out, "warning: could not enable Hermes codex_app_server runtime: %v\n", err)
		fmt.Fprintln(out, "Hermes OpenAI Codex provider may fail until you run: hermes config set model.openai_runtime codex_app_server")
		return
	}
	fmt.Fprintln(out, "Hermes OpenAI/Codex runtime set to codex_app_server.")
}

func runInstallCommands(out io.Writer, commands [][]string) error {
	var lastErr error
	for _, command := range commands {
		if err := runCommand(out, command); err != nil {
			lastErr = err
			fmt.Fprintf(out, "installer failed, trying next fallback if available: %v\n", err)
			continue
		}
		return nil
	}
	if lastErr != nil {
		return lastErr
	}
	return nil
}

func markAgent(agent config.AgentCmd, status string) config.AgentCmd {
	agent.InstallStatus = status
	enabled := status == "configured"
	agent.Enabled = config.BoolPtr(enabled)
	return agent
}

func markLanguageServer(server config.LanguageServerCmd, status string) config.LanguageServerCmd {
	server.InstallStatus = status
	enabled := status == "configured"
	server.Enabled = config.BoolPtr(enabled)
	return server
}

func normalizeSetupIDs(ids []string) ([]string, bool) {
	var normalized []string
	for _, id := range ids {
		id = strings.ToLower(strings.TrimSpace(id))
		if id == "" {
			continue
		}
		switch id {
		case "none", "skip", "no", "n", "false", "off":
			return nil, true
		case "all":
			normalized = append(normalized, "typescript", "python", "vue")
		default:
			normalized = append(normalized, id)
		}
	}
	return normalized, false
}

func runCommand(out io.Writer, args []string) error {
	if len(args) == 0 {
		return nil
	}
	fmt.Fprintf(out, "running: %s\n", strings.Join(args, " "))
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, args[0], args[1:]...)
	cmd.Stdout = out
	cmd.Stderr = out
	return cmd.Run()
}

func runCommandCapture(args []string) (string, error) {
	if len(args) == 0 {
		return "", nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, args[0], args[1:]...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	return out.String(), err
}

func withResolvedCommand(args []string, expectedCommand string, resolvedCommand string) []string {
	if len(args) == 0 || resolvedCommand == "" {
		return args
	}
	copied := append([]string(nil), args...)
	if copied[0] == expectedCommand {
		copied[0] = resolvedCommand
	}
	return copied
}

func resolveCommandPath(command string) (string, bool) {
	command = strings.TrimSpace(command)
	if command == "" {
		return "", false
	}
	if strings.ContainsAny(command, `/\`) {
		if isEditorExtensionCodexPath(command) {
			return "", false
		}
		if isExecutable(command) {
			return command, true
		}
		return "", false
	}
	if path, err := exec.LookPath(command); err == nil && isExecutable(path) && !isEditorExtensionCodexPath(path) {
		return path, true
	}
	for _, path := range fallbackCommandPaths(command) {
		if isExecutable(path) {
			return path, true
		}
	}
	return "", false
}

func fallbackCommandPaths(command string) []string {
	paths := []string{}
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		paths = append([]string{filepath.Join(home, ".local", "bin", command)}, paths...)
	}
	if os.Getenv("AIRCODE_DISABLE_SYSTEM_COMMAND_FALLBACKS") != "1" {
		paths = append(paths,
			filepath.Join("/opt/homebrew/bin", command),
			filepath.Join("/usr/local/bin", command),
		)
	}
	return paths
}

func isEditorExtensionCodexPath(path string) bool {
	normalized := filepath.ToSlash(path)
	return strings.Contains(normalized, "/.vscode/extensions/openai.chatgpt-") ||
		strings.Contains(normalized, "/.cursor/extensions/openai.chatgpt-")
}

func isExecutable(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir() && info.Mode()&0o111 != 0
}

func splitIDs(value string) []string {
	parts := strings.Split(value, ",")
	var ids []string
	for _, part := range parts {
		id := strings.ToLower(strings.TrimSpace(part))
		if id != "" {
			ids = append(ids, id)
		}
	}
	return ids
}
