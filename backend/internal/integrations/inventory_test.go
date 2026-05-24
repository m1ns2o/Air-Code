package integrations

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/air-code/air-code/backend/internal/config"
)

func TestListInventoryDiscoversMCPAndLocalItems(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	if err := os.MkdirAll(filepath.Join(home, ".codex", "skills", "project-skill"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(home, ".hermes", "hooks"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, ".hermes", "hooks", "post.sh"), []byte("#!/bin/sh\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(home, ".codex", "cache", "codex_apps_tools"), 0o755); err != nil {
		t.Fatal(err)
	}
	appCache := `{"tools":[{"connector_id":"connector-github","connector_name":"GitHub","namespace_description":"Access repositories","plugin_display_names":[]}]}`
	if err := os.WriteFile(filepath.Join(home, ".codex", "cache", "codex_apps_tools", "apps.json"), []byte(appCache), 0o644); err != nil {
		t.Fatal(err)
	}
	fake := fakeProvider(t, `#!/bin/sh
if [ "$1" = "mcp" ] && [ "$2" = "list" ]; then
  echo "Name  Command  Args  Env  Cwd  Status  Auth"
  echo "docs  /tmp/docs-mcp  -  -  -  enabled  Unsupported"
  exit 0
fi
exit 1
`)

	inventory := List(map[string]config.AgentCmd{
		"codex": {Enabled: config.BoolPtr(true), Command: fake},
	})

	if !hasItem(inventory, "codex", "mcp", "docs") {
		t.Fatalf("missing codex MCP item: %#v", inventory.Sections)
	}
	if !hasItem(inventory, "codex", "skill", "project-skill") {
		t.Fatalf("missing codex skill item: %#v", inventory.Sections)
	}
	if !hasItem(inventory, "hermes", "hook", "post.sh") {
		t.Fatalf("missing hermes hook item: %#v", inventory.Sections)
	}
	if !hasItem(inventory, "codex", "app", "GitHub") {
		t.Fatalf("missing codex cached app item: %#v", inventory.Sections)
	}
}

func TestListInventoryEncodesEmptySectionsAsArrays(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	payload, err := json.Marshal(List(nil))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(payload), `"items":null`) {
		t.Fatalf("inventory should encode empty item lists as arrays: %s", payload)
	}
}

func TestManageRemovesMCPWithProviderCommand(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	marker := filepath.Join(home, "removed")
	fake := fakeProvider(t, `#!/bin/sh
if [ "$1" = "mcp" ] && [ "$2" = "remove" ] && [ "$3" = "docs" ]; then
  echo "$3" > "`+marker+`"
  exit 0
fi
exit 1
`)

	response, err := Manage(ActionRequest{
		Action:   "remove",
		Provider: "codex",
		Kind:     "mcp",
		Name:     "docs",
	}, map[string]config.AgentCmd{
		"codex": {Enabled: config.BoolPtr(true), Command: fake},
	})
	if err != nil {
		t.Fatal(err)
	}
	if response.Status != "removed" {
		t.Fatalf("status=%q", response.Status)
	}
	content, err := os.ReadFile(marker)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != "docs\n" {
		t.Fatalf("marker=%q", content)
	}
}

func TestManageRunsMCPListWithProviderCommand(t *testing.T) {
	fake := fakeProvider(t, `#!/bin/sh
if [ "$1" = "mcp" ] && [ "$2" = "list" ]; then
  echo "Name  Command  Args  Env  Cwd  Status  Auth"
  echo "docs  /tmp/docs-mcp  -  -  -  enabled  Unsupported"
  exit 0
fi
exit 1
`)

	response, err := Manage(ActionRequest{
		Action:   "command",
		Provider: "codex",
		Kind:     "mcp",
		Name:     "list",
	}, map[string]config.AgentCmd{
		"codex": {Enabled: config.BoolPtr(true), Command: fake},
	})
	if err != nil {
		t.Fatal(err)
	}
	if response.Status != "completed" {
		t.Fatalf("status=%q", response.Status)
	}
	if len(response.Command) != 3 || response.Command[1] != "mcp" || response.Command[2] != "list" {
		t.Fatalf("command=%v", response.Command)
	}
	if !strings.Contains(response.Output, "docs") {
		t.Fatalf("output=%q", response.Output)
	}
}

func TestManageRejectsUnsupportedMCPChatCommand(t *testing.T) {
	fake := fakeProvider(t, "#!/bin/sh\nexit 0\n")
	_, err := Manage(ActionRequest{
		Action:   "command",
		Provider: "codex",
		Kind:     "mcp",
		Name:     "remove",
	}, map[string]config.AgentCmd{
		"codex": {Enabled: config.BoolPtr(true), Command: fake},
	})
	if err == nil {
		t.Fatal("expected unsupported MCP command to fail")
	}
}

func TestManageRunsHermesSkillsListCommand(t *testing.T) {
	fake := fakeProvider(t, `#!/bin/sh
if [ "$1" = "skills" ] && [ "$2" = "list" ]; then
  echo "installed skills"
  exit 0
fi
exit 1
`)

	response, err := Manage(ActionRequest{
		Action:   "command",
		Provider: "hermes",
		Kind:     "skills",
		Name:     "list",
	}, map[string]config.AgentCmd{
		"hermes": {Enabled: config.BoolPtr(true), Command: fake},
	})
	if err != nil {
		t.Fatal(err)
	}
	if response.Status != "completed" {
		t.Fatalf("status=%q", response.Status)
	}
	if len(response.Command) != 3 || response.Command[1] != "skills" || response.Command[2] != "list" {
		t.Fatalf("command=%v", response.Command)
	}
	if !strings.Contains(response.Output, "installed skills") {
		t.Fatalf("output=%q", response.Output)
	}
}

func TestManageRejectsProviderWithoutHeadlessSkillsCommand(t *testing.T) {
	fake := fakeProvider(t, "#!/bin/sh\nexit 0\n")
	_, err := Manage(ActionRequest{
		Action:   "command",
		Provider: "codex",
		Kind:     "skills",
		Name:     "list",
	}, map[string]config.AgentCmd{
		"codex": {Enabled: config.BoolPtr(true), Command: fake},
	})
	if err == nil {
		t.Fatal("expected unsupported skills command to fail")
	}
}

func TestRemoveLocalRejectsPathOutsideManagedRoots(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	outside := filepath.Join(home, "outside-skill")
	if err := os.MkdirAll(outside, 0o755); err != nil {
		t.Fatal(err)
	}
	_, err := Manage(ActionRequest{
		Action: "remove",
		Kind:   "skill",
		Path:   outside,
	}, nil)
	if err == nil {
		t.Fatal("expected outside root removal to fail")
	}
	if _, statErr := os.Stat(outside); statErr != nil {
		t.Fatalf("outside path should remain: %v", statErr)
	}
}

func fakeProvider(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "provider")
	if err := os.WriteFile(path, []byte(content), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func hasItem(inventory Inventory, provider, kind, name string) bool {
	for _, section := range inventory.Sections {
		for _, item := range section.Items {
			if item.Provider == provider && item.Kind == kind && item.Name == name {
				return true
			}
		}
	}
	return false
}
