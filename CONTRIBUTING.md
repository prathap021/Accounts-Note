# Contributing to Accounts Note

Thanks for helping improve this open-source project. All constructive
contributions are welcome.

## How to contribute

1. **Fork** [Accounts-Note](https://github.com/prathap021/Accounts-Note)
2. **Clone** your fork and create a feature branch:
   ```bash
   git checkout -b feature/short-description
   ```
3. Set up Firebase locally (see README) — never commit secret config files
4. Make your changes
5. Before opening a PR, run:
   ```bash
   flutter pub get
   flutter analyze
   flutter test
   ```
6. **Push** and open a **Pull Request** against `master`

## Pull request guidelines

- Keep PRs focused (one feature or fix per PR when possible)
- Explain the problem and your solution in the PR description
- Include screenshots for UI changes
- Update docs/README if behavior or setup changes
- Do not commit Firebase keys, keystores, or `.env` files

## Reporting bugs

Open a GitHub Issue with:

- What you expected
- What happened
- Steps to reproduce
- Flutter / OS version (`flutter doctor -v` summary is helpful)

## Feature ideas

Open an Issue first for larger features so we can discuss design before a
big PR.

## Code style

- Follow existing project structure (features / providers / repositories)
- Prefer clear names over clever shortcuts
- Match Dart formatting (`dart format .`)

## License

By contributing, you agree that your contributions are licensed under the
same [MIT License](LICENSE) as the project.
