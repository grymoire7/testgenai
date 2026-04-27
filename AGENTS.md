# TestGenAI

See REAMDE.md for basic description and usage.

## Setup

After cloning, install the StandardRB pre-commit hook:

```bash
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
set -e
rubyfiles=$(git diff --cached --name-only --diff-filter=ACM "*.rb" "Gemfile" | tr '\n' ' ')
[ -z "$rubyfiles" ] && exit 0
echo "Formatting staged Ruby files with standardrb"
echo "$rubyfiles" | xargs bundle exec standardrb --fix
echo "$rubyfiles" | xargs git add
exit 0
EOF
chmod +x .git/hooks/pre-commit
```

## Development Rules

- Use TDD red-green-refactor cycle for all development.


