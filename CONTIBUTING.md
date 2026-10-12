# Contributing
It's great you're thinking about contributing to make Ondu better!

## LLM policy
Since pretty much the entire codebase is LLM generated right now, so it's fine
to add contributions that are generated too. Just be transparent about it.

## Testing and Formatting
Run the tests before sending a change:

```sh
xcodebuild -scheme Ondu -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO test
```

Code is formatted with the `swift-format` that ships with Xcode; CI rejects
anything it flags:

```sh
xcrun swift-format format -i -r --parallel Ondu OnduTests
```

## License
By contributing, you agree that your contributions will be licensed under the
same license as this project (see `LICENSE`).

