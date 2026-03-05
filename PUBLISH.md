# Publishing Guide

This document walks you through publishing the Model Router hook to GitHub.

## 📁 Repository Structure

```
claude-model-router/
├── README.md                      # Main documentation
├── LICENSE                        # MIT License
├── CONTRIBUTING.md                # Contribution guidelines
├── PUBLISH.md                     # This file
├── .gitignore                     # Git ignore rules
├── install.sh                     # Installation script
├── uninstall.sh                   # Uninstallation script
├── test_hook.sh                   # Test suite
├── plugin/
│   ├── plugin.json               # Plugin metadata
│   ├── hooks/
│   │   ├── hooks.json            # Hook registration
│   │   └── model_router.py       # Main analysis script
│   └── config/
│       └── patterns.json         # Keyword patterns
├── docs/
│   ├── README.md                 # Full documentation
│   └── QUICKSTART.md             # Quick reference
└── examples/
    ├── custom_patterns.json      # Example custom patterns
    └── healthcare_patterns.json  # Healthcare-specific example
```

## 🚀 Publishing to GitHub

### Step 1: Create GitHub Repository

1. Go to https://github.com/new
2. Repository name: `claude-model-router`
3. Description: "Intelligent model routing hook for Claude Code cost optimization"
4. Public/Private: Choose based on your needs
5. **Do NOT** initialize with README (we have one)
6. Click "Create repository"

### Step 2: Initialize Git

```bash
cd ~/Desktop/claude-model-router

# Initialize git
git init

# Add all files
git add .

# Create initial commit
git commit -m "Initial commit: Claude Model Router Hook v1.0.0"
```

### Step 3: Push to GitHub

```bash
# Add remote (replace YOUR_USERNAME)
git remote add origin https://github.com/YOUR_USERNAME/claude-model-router.git

# Push to main branch
git branch -M main
git push -u origin main
```

## 📋 Post-Publishing Checklist

### GitHub Settings

- [ ] Enable Issues
- [ ] Enable Discussions (optional)
- [ ] Add topics/tags: `claude-code`, `hooks`, `cost-optimization`, `python`
- [ ] Add description and website link
- [ ] Create release v1.0.0

### Documentation

- [ ] Add badges to README (license, version)
- [ ] Add screenshot/demo GIF
- [ ] Update URLs in documentation
- [ ] Create GitHub Pages (optional)

### Sharing

- [ ] Share with team via Slack/email
- [ ] Post in Claude Code community
- [ ] Tweet/blog about it (optional)

## 📢 Sharing with Colleagues

### Email Template

```
Subject: New Tool: Claude Model Router Hook

Hi team,

I've created a hook for Claude Code that helps optimize costs by
automatically recommending the right model (Haiku/Sonnet/Opus) based
on task complexity.

🔗 Repository: https://github.com/YOUR_USERNAME/claude-model-router

📥 Installation: One command
   git clone https://github.com/YOUR_USERNAME/claude-model-router.git
   cd claude-model-router && ./install.sh

💰 Potential savings: Up to 35% on token costs

📚 Docs: Full documentation in the README

Try it out and let me know what you think!
```

### Slack Message

```
:rocket: New tool for Claude Code users!

I built a hook that analyzes your prompts and recommends the optimal
model for cost optimization.

Features:
• Multi-factor analysis (keywords, complexity, files)
• Cost comparison for each prompt
• Customizable keyword patterns
• Zero config needed

GitHub: https://github.com/YOUR_USERNAME/claude-model-router
Install: `./install.sh` (one command)

Try the healthcare example patterns if you work with patient data!
```

## 🎯 Creating a Release

### Tag the Release

```bash
git tag -a v1.0.0 -m "Version 1.0.0: Initial release"
git push origin v1.0.0
```

### GitHub Release Page

1. Go to repository → Releases → Create new release
2. Tag: `v1.0.0`
3. Title: "Version 1.0.0 - Initial Release"
4. Description:

```markdown
## 🎉 Initial Release

Multi-factor model routing hook for Claude Code cost optimization.

### ✨ Features

- Multi-factor prompt analysis (keywords, tool complexity, file context, inference depth)
- Automatic model recommendations (Haiku/Sonnet/Opus)
- Cost comparison display
- Customizable keyword patterns
- One-command installation
- Healthcare-specific examples included

### 📦 Installation

```bash
git clone https://github.com/YOUR_USERNAME/claude-model-router.git
cd claude-model-router
chmod +x install.sh
./install.sh
```

### 💰 Cost Savings

Potential savings up to 35% by routing:
- 60% simple queries → Haiku ($0.25/1M)
- 35% standard code → Sonnet ($3.00/1M)
- 5% complex tasks → Opus ($15.00/1M)

### 📚 Documentation

- [README](README.md) - Full documentation
- [Quick Start](docs/QUICKSTART.md) - Quick reference
- [Contributing](CONTRIBUTING.md) - How to contribute
- [Examples](examples/) - Custom patterns

### 🧪 Tested On

- Claude Code latest
- Python 3.8+
- macOS, Linux, WSL
```

## 🔄 Future Updates

### Versioning

Use semantic versioning:
- **1.0.0** → Initial release
- **1.0.1** → Bug fixes
- **1.1.0** → New features (backwards compatible)
- **2.0.0** → Breaking changes

### Release Process

```bash
# Make changes
git add .
git commit -m "Feature: Add usage analytics"

# Tag release
git tag -a v1.1.0 -m "Version 1.1.0: Usage analytics"

# Push
git push origin main
git push origin v1.1.0

# Create GitHub release
# Go to GitHub → Releases → Create new release
```

## 📊 Analytics (Optional)

Track adoption with:
- GitHub stars/forks
- Issue/discussion activity
- Download counts (releases)
- Community feedback

## 🎨 Optional Enhancements

### Add Demo GIF

Record terminal session:
```bash
# Install asciinema
brew install asciinema

# Record demo
asciinema rec demo.cast

# Convert to GIF using agg
agg demo.cast demo.gif

# Add to README
```

### Add Badges

```markdown
[![GitHub stars](https://img.shields.io/github/stars/YOUR_USERNAME/claude-model-router?style=social)](https://github.com/YOUR_USERNAME/claude-model-router/stargazers)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
```

### Create GitHub Pages

```bash
# Enable GitHub Pages in repo settings
# Point to main branch /docs folder
# Your docs will be live at:
# https://YOUR_USERNAME.github.io/claude-model-router/
```

## 🤝 Community Building

### Encourage Contributions

- Respond to issues promptly
- Welcome PRs with clear guidelines
- Add good first issue labels
- Create project board for roadmap
- Document architecture for contributors

### Share Success Stories

Encourage users to share:
- Cost savings achieved
- Custom patterns created
- Integration examples
- Use cases

## ✅ Ready to Publish

Your repository is ready! Just:

1. Create GitHub repo
2. Push code (`git init`, `git add .`, `git commit`, `git push`)
3. Share with team
4. Iterate based on feedback

Good luck! 🚀
