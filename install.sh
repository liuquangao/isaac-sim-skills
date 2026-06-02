#!/usr/bin/env bash
# install.sh — Install Isaac Sim Claude Code skills to ~/.claude/skills/
#
# Usage:
#   ./install.sh                              # install all skills
#   ./install.sh isaac-sim-person-simulation  # install one skill
#   ./install.sh skill-a skill-b              # install multiple skills

set -e

SKILLS_DIR="$HOME/.claude/skills"
REPO_SKILLS="$(cd "$(dirname "$0")/skills" && pwd)"

# Check that the skills source directory exists
if [ ! -d "$REPO_SKILLS" ]; then
    echo "Error: skills/ directory not found next to install.sh"
    exit 1
fi

mkdir -p "$SKILLS_DIR"

install_skill() {
    local name="$1"
    local src="$REPO_SKILLS/$name"

    if [ ! -d "$src" ]; then
        echo "Error: skill '$name' not found in skills/"
        echo "Available skills:"
        ls "$REPO_SKILLS"
        exit 1
    fi

    local dest="$SKILLS_DIR/$name"
    if [ -d "$dest" ]; then
        echo "Updating : $name"
    else
        echo "Installing: $name"
    fi

    cp -r "$src" "$SKILLS_DIR/"
}

if [ $# -eq 0 ]; then
    for skill_dir in "$REPO_SKILLS"/*/; do
        [ -d "$skill_dir" ] || continue
        install_skill "$(basename "$skill_dir")"
    done
else
    for name in "$@"; do
        install_skill "$name"
    done
fi

echo ""
echo "Done. Restart Claude Code (or reload the window) to activate new skills."
echo "Skills installed to: $SKILLS_DIR"
