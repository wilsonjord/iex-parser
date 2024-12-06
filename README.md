# iex-parser

A parser that reads IEX TOPS market data, and outputs it to json.

# Installation

Install from a [prebuilt binary](https://github.com/wilsonjord/iex-parser/releases/latest), or build from source.

## From source

```shell
git clone git@github.com/wilsonjord/iex-parser.git
cd iex-parser
dub build --build=release
```

# Usage

`iex-parser` reads [IEX Historical Data](https://iextrading.com/trading/market-data) (gzip compressed pcap files),
and prints to stdout.

```shell
iex-parser data_feeds.pcap.gz
```
