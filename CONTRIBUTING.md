# Contributing to Claude Model Router

Thanks for your interest in contributing! This guide will help you get started.

## 🚀 Quick Start

1. **Fork the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/claude-model-router.git
   cd claude-model-router
   ```

2. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Edit files in `plugin/` directory
   - Update tests if needed
   - Update documentation

4. **Test your changes**
   ```bash
   ./install.sh
   # Test with Claude Code
   ./test_hook.sh
   ```

5. **Submit a pull request**

## 📋 Development Guidelines

### Code Style

- **Python**: Follow PEP 8 style guide
- **JSON**: Use 2-space indentation
- **Shell**: Use bash with `set -e` for safety
- **Comments**: Explain why, not what

### Testing

Before submitting, ensure:

```bash
# Hook runs without errors
echo '{"prompt":"test"}' | python3 plugin/hooks/model_router.py

# All test cases pass
./test_hook.sh

# No Python syntax errors
python3 -m py_compile plugin/hooks/model_router.py

# JSON is valid
python3 -m json.tool plugin/config/patterns.json > /dev/null
```

### Documentation

Update documentation for:
- New features
- Changed behavior
- New configuration options
- Examples

Files to update:
- `README.md` - Main docs
- `docs/README.md` - Full documentation
- `docs/QUICKSTART.md` - Quick reference
- `examples/` - Add examples

## 💡 Ideas for Contributions

### High Priority

- [ ] Usage analytics and cost tracking
- [ ] Machine learning-based classification
- [ ] Integration tests with Claude Code
- [ ] Performance benchmarks

### Medium Priority

- [ ] Team collaboration features
- [ ] Pattern sharing marketplace
- [ ] Web dashboard for cost visualization
- [ ] Slack/Discord notifications

### Low Priority

- [ ] Alternative scoring algorithms
- [ ] Language-specific patterns
- [ ] Framework-specific keywords
- [ ] IDE integration

## 🔧 Adding New Features

### Adding a New Scoring Factor

1. Add analysis function to `model_router.py`:
   ```python
   def analyze_new_factor(prompt):
       """Your new factor description"""
       # Your logic here
       return 'score_value'
   ```

2. Update main analysis:
   ```python
   analysis = {
       'keywords': analyze_prompt_keywords(prompt, patterns),
       'tool_complexity': analyze_tool_complexity(prompt),
       'file_context': analyze_file_context(prompt),
       'inference_depth': analyze_inference_depth(prompt),
       'new_factor': analyze_new_factor(prompt)  # Add here
   }
   ```

3. Update scoring in `recommend_model()`:
   ```python
   # Factor 5: Your new factor
   if analysis['new_factor'] == 'high':
       score += 2
   ```

4. Update output format
5. Add tests
6. Update documentation

### Adding New Keywords

1. Edit `plugin/config/patterns.json`
2. Add examples to `examples/` directory
3. Document in README

### Improving Classification

Current accuracy can be improved by:
- Adding more keyword patterns
- Tuning score thresholds
- Adding context-aware analysis
- Machine learning classification

## 🐛 Bug Reports

Include:
- Claude Code version
- Python version
- OS and version
- Steps to reproduce
- Expected vs actual behavior
- Hook output if available

## 📝 Pull Request Process

1. **Update documentation** for any changes
2. **Add tests** for new features
3. **Run test suite** before submitting
4. **Describe changes** clearly in PR description
5. **Link issues** if fixing bugs

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Performance improvement

## Testing
- [ ] Tested with test_hook.sh
- [ ] Tested with Claude Code
- [ ] Added new tests if needed

## Checklist
- [ ] Code follows style guidelines
- [ ] Documentation updated
- [ ] Tests pass
- [ ] No breaking changes (or documented)
```

## 🎯 Coding Standards

### Python

```python
# Good
def analyze_complexity(prompt: str) -> str:
    """
    Analyze prompt complexity.

    Args:
        prompt: User's input prompt

    Returns:
        Complexity level: 'low', 'medium', or 'high'
    """
    if len(prompt) < 50:
        return 'low'
    return 'medium'

# Avoid
def doStuff(p):
    if len(p)<50:return 'low'
    return 'medium'
```

### JSON

```json
{
  "haiku_keywords": [
    "simple",
    "quick"
  ],
  "notes": "Use 2-space indentation"
}
```

## 🏗️ Architecture

```
model_router.py (main script)
    ├── load_patterns() - Load keyword config
    ├── analyze_prompt_keywords() - Factor 1
    ├── analyze_tool_complexity() - Factor 2
    ├── analyze_file_context() - Factor 3
    ├── analyze_inference_depth() - Factor 4
    ├── recommend_model() - Combine factors
    └── main() - Entry point
```

## 📚 Resources

- [Claude Code Hooks Documentation](https://docs.anthropic.com/claude-code/hooks)
- [PEP 8 Style Guide](https://pep8.org/)
- [Semantic Versioning](https://semver.org/)

## 📞 Contact

Questions? Open an issue or reach out to the maintainer.

## 🙏 Contributors

Thank you to all contributors!

<!-- Add contributors here -->
