package mcp

import "testing"

func TestFallbackCatalogFiltersItems(t *testing.T) {
	items := fallbackCatalog("fetch", "official")
	if len(items) != 1 {
		t.Fatalf("items=%#v", items)
	}
	if items[0].Command != "uvx" || items[0].Args[0] != "mcp-server-fetch" {
		t.Fatalf("item=%#v", items[0])
	}
}

func TestPackageCommandMapsNPMAndPyPI(t *testing.T) {
	command, args := packageCommand("npm", "@modelcontextprotocol/server-filesystem", []string{"/tmp"})
	if command != "npx" || len(args) != 3 || args[0] != "-y" || args[1] != "@modelcontextprotocol/server-filesystem" {
		t.Fatalf("npm command=%q args=%#v", command, args)
	}
	command, args = packageCommand("pypi", "mcp-server-fetch", nil)
	if command != "uvx" || len(args) != 1 || args[0] != "mcp-server-fetch" {
		t.Fatalf("pypi command=%q args=%#v", command, args)
	}
}
