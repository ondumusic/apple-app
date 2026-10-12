# Ondu for iPhone and Mac
The official iPhone and Mac clients for [Ondu](https://ondumusic.com).

## Disclaimer
This repo contains almost entirely LLM generated code and documentation, it was
developed over months of iterations and manual testing on my own devices with my
real music library.

## Requirements
- iOS 26.2 or later, or macOS 15.7 or later
- An Ondu server you host yourself, see the [setup guide](https://ondumusic.com/setup.html)

## Building
You'll need Xcode 27 to build this project.

- Open `Ondu.xcodeproj`
- Select the **Ondu** scheme
- Run

By default it does not configure a signing team, to sign with your own team and/
or change identifiers you can create a `Config/Local.xcconfig` file. See
[`Config/README.md`](Config/README.md) for more information.

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License
Ondu is distributed under the terms of the MIT license.

See [LICENSE](LICENSE) for details.
