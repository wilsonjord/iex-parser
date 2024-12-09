import std.stdio;
import std.algorithm;
import std.range;
import std.bitmanip : Endian, peek, swapEndian;
import std.exception;

import pcapng;
import iex;

import mir.ser.json;
import iopipe.bufpipe;
import iopipe.zip;
import iopipe.refc;
import std.io;
import commandr;

Endian _endian;
void toggleEndian() {
    _endian = (_endian == Endian.bigEndian) ? Endian.littleEndian : Endian.bigEndian;
}

auto setEndian(Endian e) {
    if (e == _endian) return false;
    _endian = e;
    return true;
}

auto read(T, R) (ref R range) {
    scope(exit) {
        range.release(T.sizeof);
    }

    final switch (_endian) {
        case Endian.bigEndian:
            return peek!(T, Endian.bigEndian)(range.window);
        case Endian.littleEndian:
            return peek!(T, Endian.littleEndian)(range.window);
    }
}

auto iopPeek(T, R) (ref R range) {
    final switch (_endian) {
        case Endian.bigEndian:
            return peek!(T, Endian.bigEndian)(range.window);
        case Endian.littleEndian:
            return peek!(T, Endian.littleEndian)(range.window);
    }
}

void main(string[] args) {
    static immutable string[] VERSION = import(".VERSION").split;
    assert(!VERSION.empty);

    auto cmd = new Program("IEX Parser", VERSION.front)
        .author("Jordan K. Wilson <wilsonjord@gmail.com>")
        .add(new Argument("file", "IEX TOPS file"))
        .parse(args);

    auto data = std.io.File(cmd.arg("file"), Mode.read)
        .refCounted
        .bufd
        .unzip;

    while (true) {
        data.ensureElems(4096);
        if (data.window.count == 0) break;

        // read block type
        auto blockType = data.read!uint;
        switch (blockType) {
            default:
                // skip
                auto blockLength = data.read!uint;

                data.ensureElems(blockLength);

                // block length includes block type, and length, which have already been read
                data.release(blockLength - (blockType.sizeof + blockLength.sizeof));
                break;
            case BlockType.enhancedPacket:
                // this block contains the packet data we care about

                auto blockLength = data.read!uint;
                data.ensureElems(blockLength);

                // block length includes block type, and length, which have already been read
                scope(exit) data.release(blockLength - (blockType.sizeof + blockLength.sizeof));

                auto payload = data.window.take(blockLength);

                // skip uninteresting fields
                payload = payload.drop(
                    uint.sizeof + // interface ID
                    ulong.sizeof + // timestamp
                    uint.sizeof + // captured packet length
                    uint.sizeof // original packet length
                );

                payload = payload.drop(42); // data starts at offset 43 // TODO support others like SNAP frames?

                // IEX specific data starts here, in little endian format

                import std.bitmanip : read;
                auto messageCount = payload.drop(14).peek!(ushort, Endian.littleEndian);
                payload = payload.drop(40); // drop the IEX-TP header

                foreach (i; 0..messageCount) {
                    auto messageBlockLength = payload.read!(ushort, Endian.littleEndian);
                    if (messageBlockLength == 0) continue;

                    auto messageType = payload.peek!(ubyte, Endian.littleEndian);
                    scope(exit) payload = payload.drop(messageBlockLength);
                    switch (messageType) {
                        default:
                            writefln("TODO %X", messageType);
                            assert(0);
                            break;
                        case MessageType.priceLevelUpdateBuySide:
                        case MessageType.priceLevelUpdateSellSide:
                            payload.ptr.getMessage!PriceLevelUpdateMessage.serializeJson.writeln;
                            break;
                        case MessageType.systemEvent:
                            payload.ptr.getMessage!SystemEventMessage.serializeJson.writeln;
                            break;
                        case MessageType.quoteUpdate:
                            payload.ptr.getMessage!QuoteUpdateMessage.serializeJson.writeln;
                            break;
                        case MessageType.shortSalePriceTestStatus:
                            payload.ptr.getMessage!ShortSalePriceTestStatusMessage.serializeJson.writeln;
                            break;
                        case MessageType.tradeReport:
                            payload.ptr.getMessage!TradeReportMessage.serializeJson.writeln;
                            break;
                        case MessageType.retailLiquidityIndicator:
                            payload.ptr.getMessage!RetailLiquidityIndicatorMessage.serializeJson.writeln;
                            break;
                        case MessageType.auctionInformation:
                            payload.ptr.getMessage!AuctionInformationMessage.serializeJson.writeln;
                            break;
                        case MessageType.tradingStatus:
                            payload.ptr.getMessage!TradingStatusMessage.serializeJson.writeln;
                            break;
                        case MessageType.operationalHaltStatus:
                            payload.ptr.getMessage!OperationalHaltStatusMessage.serializeJson.writeln;
                            break;
                        case MessageType.securityDirectory:
                            payload.ptr.getMessage!SecurityDirectoryMessage.serializeJson.writeln;
                            break;
                        case MessageType.officialPrice:
                            payload.ptr.getMessage!OfficialPriceMessage.serializeJson.writeln;
                            break;
                    }
                }

                break;
            case BlockType.sectionHeader:
                // use section header to set endianness

                auto blockLength = data.read!uint;
                auto magic = data.read!uint;

                if (magic != MagicNumber) {
                    // swap endian
                    toggleEndian;
                    blockLength = blockLength.swapEndian;
                }

                data.ensureElems(blockLength);

                // block length includes block type, length, and endian, which has already been read
                data.release(blockLength - (blockType.sizeof + blockLength.sizeof + magic.sizeof));
                break;
            case BlockType.interfaceDescription:
                // use interface block to set Link Layer type

                auto blockLength = data.read!uint;
                data.ensureElems(blockLength);

                auto linkType = data.iopPeek!ushort;
                enforce(linkType == LinkType.ethernet, "only IEEE 802.3 Ethernet link type is supported");

                // block length includes block type, and length, which have already been read
                data.release(blockLength - (blockType.sizeof + blockLength.sizeof));
        }
    }
}
