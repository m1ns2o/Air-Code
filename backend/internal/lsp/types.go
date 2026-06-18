package lsp

type Position struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}

type Range struct {
	Start Position `json:"start"`
	End   Position `json:"end"`
}

type Diagnostic struct {
	Range    Range  `json:"range"`
	Severity int    `json:"severity,omitempty"`
	Source   string `json:"source,omitempty"`
	Message  string `json:"message"`
}

type Capability struct {
	ID             string   `json:"id"`
	DisplayName    string   `json:"displayName"`
	Installed      bool     `json:"installed"`
	Configured     bool     `json:"configured"`
	Enabled        bool     `json:"enabled"`
	Command        string   `json:"command,omitempty"`
	FileExtensions []string `json:"fileExtensions"`
	InstallStatus  string   `json:"installStatus,omitempty"`
	InstallHint    string   `json:"installHint"`
}

type DocumentRequest struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

type DocumentSyncResponse struct {
	Path     string `json:"path"`
	ServerID string `json:"serverId,omitempty"`
	Synced   bool   `json:"synced"`
	Disabled bool   `json:"disabled,omitempty"`
	Message  string `json:"message,omitempty"`
}

type PositionRequest struct {
	Path      string   `json:"path"`
	Content   string   `json:"content,omitempty"`
	Position  Position `json:"position"`
	Trigger   string   `json:"trigger,omitempty"`
	Prefix    string   `json:"prefix,omitempty"`
	OnlyKinds []string `json:"onlyKinds,omitempty"`
}

type CompletionResponse struct {
	Items []CompletionItem `json:"items"`
}

type CompletionItem struct {
	Label      string `json:"label"`
	Detail     string `json:"detail,omitempty"`
	Kind       int    `json:"kind,omitempty"`
	InsertText string `json:"insertText,omitempty"`
	Range      *Range `json:"range,omitempty"`
}

type HoverResponse struct {
	Contents string `json:"contents"`
	Range    *Range `json:"range,omitempty"`
}

type DefinitionResponse struct {
	Locations []Location `json:"locations"`
}

type Location struct {
	Path     string `json:"path"`
	URI      string `json:"uri,omitempty"`
	Range    Range  `json:"range"`
	External bool   `json:"external"`
}

type CodeActionResponse struct {
	Actions []CodeAction `json:"actions"`
}

type CodeAction struct {
	Title       string              `json:"title"`
	Kind        string              `json:"kind,omitempty"`
	IsPreferred bool                `json:"isPreferred,omitempty"`
	Edit        *WorkspaceEdit      `json:"edit,omitempty"`
	Command     *Command            `json:"command,omitempty"`
	Disabled    *CodeActionDisabled `json:"disabled,omitempty"`
}

type CodeActionDisabled struct {
	Reason string `json:"reason"`
}

type Command struct {
	Title   string `json:"title,omitempty"`
	Command string `json:"command"`
}

type TextEdit struct {
	Range   Range  `json:"range"`
	NewText string `json:"newText"`
}

type WorkspaceEdit struct {
	Changes         map[string][]TextEdit `json:"changes,omitempty"`
	DocumentChanges []TextDocumentEdit    `json:"documentChanges,omitempty"`
}

type TextDocumentIdentifier struct {
	URI string `json:"uri"`
}

type TextDocumentEdit struct {
	TextDocument TextDocumentIdentifier `json:"textDocument"`
	Edits        []TextEdit             `json:"edits"`
}

type ApplyCodeActionRequest struct {
	Path    string     `json:"path"`
	Content string     `json:"content,omitempty"`
	Action  CodeAction `json:"action"`
}

type RenameRequest struct {
	Path     string   `json:"path"`
	Content  string   `json:"content,omitempty"`
	Position Position `json:"position"`
	NewName  string   `json:"newName"`
}

type WorkspaceEditResponse struct {
	Applied      bool     `json:"applied"`
	ChangedFiles []string `json:"changedFiles"`
	Message      string   `json:"message,omitempty"`
}

type DiagnosticsResponse struct {
	Path        string       `json:"path,omitempty"`
	Diagnostics []Diagnostic `json:"diagnostics"`
}
