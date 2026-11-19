package manager

import (
	"fmt"
	"strings"
)

// completion <shell>: script de autocompletado. Los nombres de las versiones
// instaladas salen de 'godot-manager __versions' cada vez, asi que siempre
// estan al dia.

var completionCommands = []string{
	"list", "list-remote", "install", "symbols", "templates", "add", "remove",
	"set", "set-local", "which", "run", "launch", "plugins", "outdated",
	"upgrade", "prune", "path", "self-update", "completion", "version", "help",
}

// Comandos cuyo primer argumento es una version instalada.
var versionArgCommands = []string{"symbols", "remove", "set", "set-local", "launch", "upgrade"}

// Las opciones de cada comando (y los argumentos fijos).
var completionOptions = map[string][]string{
	"list-remote": {"stable", "dev", "latest"},
	"install":     {"--mono", "--debugsymbols", "--templates", "--platforms=", "--yes"},
	"templates":   {"--mono", "--platforms=", "--debugsymbols", "--debugsymbolsonly", "--yes"},
	"add":         {"--symlink", "--force"},
	"remove":      {"--yes", "--templates"},
	"set-local":   {"--unset"},
	"run":         {"--detach"},
	"launch":      {"--detach"},
	"plugins":     {"list", "enable", "disable", "remove", "--yes"},
	"prune":       {"--dry-run", "--yes"},
	"path":        {"add", "remove"},
	"self-update": {"--check", "--yes"},
	"completion":  {"bash", "zsh", "fish", "powershell"},
}

func cmdVersionsForCompletion() {
	for _, v := range installedVersions() {
		if _, ok := versionBinary(v); ok {
			fmt.Println(v)
		}
	}
}

func cmdCompletion(shell string) error {
	var script string
	switch shell {
	case "bash":
		script = bashCompletion()
	case "zsh":
		script = "#compdef godot-manager\nautoload -U bashcompinit && bashcompinit\n" + bashCompletion()
	case "fish":
		script = fishCompletion()
	case "powershell", "pwsh":
		script = powershellCompletion()
	default:
		return errf(codeInvalidArgs, "uso: godot-manager completion bash|zsh|fish|powershell")
	}
	fmt.Print(script)
	return nil
}

func bashCompletion() string {
	var cases strings.Builder
	for _, c := range completionCommands {
		opts := completionOptions[c]
		if len(opts) == 0 {
			continue
		}
		fmt.Fprintf(&cases, "        %s) opts=%q ;;\n", c, strings.Join(opts, " "))
	}
	return fmt.Sprintf(`# godot-manager: autocompletado para bash
_godot_manager() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    local i cmd="" pos=0
    for ((i = 1; i < COMP_CWORD; i++)); do
        case ${COMP_WORDS[i]} in
            --json) ;;
            --dir|-C) ((i++)) ;;
            -*) ;;
            *) if [[ -z $cmd ]]; then cmd=${COMP_WORDS[i]}; else ((pos++)); fi ;;
        esac
    done
    if [[ ${COMP_WORDS[COMP_CWORD-1]} == --dir || ${COMP_WORDS[COMP_CWORD-1]} == -C ]]; then
        COMPREPLY=($(compgen -d -- "$cur"))
        return
    fi
    if [[ -z $cmd ]]; then
        COMPREPLY=($(compgen -W "%s --json --dir" -- "$cur"))
        return
    fi
    local opts=""
    case $cmd in
%s    esac
    case $cmd in
        %s)
            if ((pos == 0)) && [[ $cur != -* ]]; then
                opts="$opts $(godot-manager __versions 2>/dev/null)"
            fi ;;
        add)
            if ((pos == 1)); then COMPREPLY=($(compgen -f -- "$cur")); return; fi ;;
        prune)
            COMPREPLY=($(compgen -W "$opts" -- "$cur") $(compgen -d -- "$cur")); return ;;
    esac
    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
}
complete -F _godot_manager godot-manager
`, strings.Join(completionCommands, " "), cases.String(), strings.Join(versionArgCommands, "|"))
}

func fishCompletion() string {
	var b strings.Builder
	b.WriteString("# godot-manager: autocompletado para fish\n")
	b.WriteString("complete -c godot-manager -f\n")
	fmt.Fprintf(&b, "complete -c godot-manager -n __fish_use_subcommand -a %q\n", strings.Join(completionCommands, " "))
	b.WriteString("complete -c godot-manager -n __fish_use_subcommand -l json -d 'Salida en JSON'\n")
	b.WriteString("complete -c godot-manager -n __fish_use_subcommand -l dir -s C -r -a '(__fish_complete_directories)'\n")
	fmt.Fprintf(&b, "complete -c godot-manager -n '__fish_seen_subcommand_from %s' -a '(godot-manager __versions 2>/dev/null)'\n", strings.Join(versionArgCommands, " "))
	for _, c := range completionCommands {
		for _, o := range completionOptions[c] {
			if name, ok := strings.CutPrefix(o, "--"); ok {
				name = strings.TrimSuffix(name, "=")
				fmt.Fprintf(&b, "complete -c godot-manager -n '__fish_seen_subcommand_from %s' -l %s\n", c, name)
			} else {
				fmt.Fprintf(&b, "complete -c godot-manager -n '__fish_seen_subcommand_from %s' -a %s\n", c, o)
			}
		}
	}
	b.WriteString("complete -c godot-manager -n '__fish_seen_subcommand_from add' -F\n")
	b.WriteString("complete -c godot-manager -n '__fish_seen_subcommand_from prune' -a '(__fish_complete_directories)'\n")
	return b.String()
}

func powershellCompletion() string {
	var opts strings.Builder
	for _, c := range completionCommands {
		if o := completionOptions[c]; len(o) > 0 {
			fmt.Fprintf(&opts, "        '%s' = @('%s')\n", c, strings.Join(o, "', '"))
		}
	}
	return fmt.Sprintf(`# godot-manager: autocompletado para PowerShell
Register-ArgumentCompleter -Native -CommandName godot-manager, godot-manager.exe -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $commands = @('%s')
    $versionArg = @('%s')
    $options = @{
%s    }
    $words = @($commandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.ToString() })
    if ($wordToComplete -ne '' -and $words.Count -gt 0) { $words = @($words | Select-Object -SkipLast 1) }
    $cmd = $null
    $pos = 0
    for ($i = 0; $i -lt $words.Count; $i++) {
        $w = $words[$i]
        if ($w -eq '--dir' -or $w -eq '-C') { $i++; continue }
        if ($w.StartsWith('-')) { continue }
        if ($null -eq $cmd) { $cmd = $w } else { $pos++ }
    }
    if ($null -eq $cmd) {
        $candidates = $commands + @('--json', '--dir')
    } else {
        $candidates = @($options[$cmd])
        if ($versionArg -contains $cmd -and $pos -eq 0 -and -not $wordToComplete.StartsWith('-')) {
            $candidates += @(godot-manager __versions 2>$null)
        }
    }
    $candidates | Where-Object { $_ -and $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
`, strings.Join(completionCommands, "', '"), strings.Join(versionArgCommands, "', '"), opts.String())
}
