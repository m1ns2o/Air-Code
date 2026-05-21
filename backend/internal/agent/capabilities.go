package agent

import (
	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/setup"
)

func Capabilities(configs map[string]config.AgentCmd) []setup.Capability {
	return setup.CapabilityList(configs)
}
