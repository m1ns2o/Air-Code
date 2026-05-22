package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/events"
	serverinstall "github.com/air-code/air-code/backend/internal/install"
	"github.com/air-code/air-code/backend/internal/project"
	"github.com/air-code/air-code/backend/internal/server"
	"github.com/air-code/air-code/backend/internal/setup"
	"github.com/air-code/air-code/backend/internal/watcher"
)

func main() {
	args := os.Args[1:]
	command := "serve"
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		command = args[0]
		args = args[1:]
	}
	switch command {
	case "serve":
		serve(args)
	case "setup":
		runSetup(args)
	case "doctor":
		runDoctor(args)
	case "install":
		runInstall(args)
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\nusage: aircoded [serve|setup|doctor|install] -config config.json\n", command)
		os.Exit(2)
	}
}

func serve(args []string) {
	flags := flag.NewFlagSet("serve", flag.ExitOnError)
	configPath := flags.String("config", "config.json", "path to config file")
	addr := flags.String("addr", "", "override listen address")
	_ = flags.Parse(args)

	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	if *addr != "" {
		cfg.Addr = *addr
	}
	store, err := project.NewStore(cfg)
	if err != nil {
		log.Fatalf("load projects: %v", err)
	}
	hub := events.NewHub()
	app := server.New(cfg, store, hub)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go watcher.NewPoller(store, hub).Start(ctx)

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           app.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	log.Printf("aircoded listening on http://%s", cfg.Addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}

func runSetup(args []string) {
	flags := flag.NewFlagSet("setup", flag.ExitOnError)
	configPath := flags.String("config", "config.json", "path to config file")
	agentList := flags.String("agents", "", "comma-separated agents to install/configure")
	yes := flags.Bool("yes", false, "run installers without interactive confirmation")
	checkOnly := flags.Bool("check-only", false, "print current agent status without installing")
	_ = flags.Parse(args)

	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	_, err = setup.Run(cfg, setup.Options{
		ConfigPath: *configPath,
		AgentIDs:   splitAgents(*agentList),
		Yes:        *yes,
		CheckOnly:  *checkOnly,
		In:         os.Stdin,
		Out:        os.Stdout,
	})
	if err != nil {
		log.Fatal(err)
	}
}

func runDoctor(args []string) {
	flags := flag.NewFlagSet("doctor", flag.ExitOnError)
	configPath := flags.String("config", "config.json", "path to config file")
	_ = flags.Parse(args)
	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	setup.Doctor(cfg, os.Stdout)
}

func runInstall(args []string) {
	flags := flag.NewFlagSet("install", flag.ExitOnError)
	prefix := flags.String("prefix", "", "install prefix, default ~/.aircode")
	binaryPath := flags.String("binary", "", "aircoded binary to install, default current executable")
	configPath := flags.String("config", "", "existing config file to copy; when omitted a deployment config is generated")
	addr := flags.String("addr", "127.0.0.1:8080", "listen address for generated config")
	token := flags.String("token", "", "auth token for generated config; random when omitted")
	workspaceRoot := flags.String("workspace-root", "", "workspace root for generated config, default <prefix>/workspaces")
	service := flags.Bool("service", false, "also install launchd/systemd user service file")
	force := flags.Bool("force", false, "overwrite installed files")
	dryRun := flags.Bool("dry-run", false, "print install paths without writing files")
	_ = flags.Parse(args)

	_, err := serverinstall.Run(serverinstall.Options{
		Prefix:        *prefix,
		BinaryPath:    *binaryPath,
		ConfigPath:    *configPath,
		Addr:          *addr,
		AuthToken:     *token,
		WorkspaceRoot: *workspaceRoot,
		Service:       *service,
		Force:         *force,
		DryRun:        *dryRun,
		Out:           os.Stdout,
	})
	if err != nil {
		log.Fatal(err)
	}
}

func splitAgents(value string) []string {
	var agents []string
	for _, item := range strings.Split(value, ",") {
		item = strings.TrimSpace(item)
		if item != "" {
			agents = append(agents, item)
		}
	}
	return agents
}
