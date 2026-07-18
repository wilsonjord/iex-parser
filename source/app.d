import std.stdio;
import std.algorithm;
import std.range;
import std.bitmanip : Endian, peek, swapEndian;
import std.exception;

import pcap;
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
    if (e == _endian)
        return false;
    _endian = e;
    return true;
}

auto read(T, R)(ref R range) {
    scope (exit) {
        range.release(T.sizeof);
    }

    final switch (_endian) {
    case Endian.bigEndian:
        return peek!(T, Endian.bigEndian)(range.window);
    case Endian.littleEndian:
        return peek!(T, Endian.littleEndian)(range.window);
    }
}

auto iopPeek(T, R)(ref R range) {
    final switch (_endian) {
    case Endian.bigEndian:
        return peek!(T, Endian.bigEndian)(range.window);
    case Endian.littleEndian:
        return peek!(T, Endian.littleEndian)(range.window);
    }
}

// takes a captured Ethernet frame, and outputs the IEX messages it contains
void processFrame(R)(R payload) {
    payload = payload.drop(42); // data starts at offset 43 // TODO support others like SNAP frames?

    // IEX specific data starts here, in little endian format

    import std.bitmanip : read;

    if (payload.count < 40)
        return; // too short to hold an IEX-TP header

    auto messageCount = payload.drop(14).peek!(ushort, Endian.littleEndian);
    payload = payload.drop(40); // drop the IEX-TP header

    // NOTE: TOPS 1.5 uses the same wire layouts as TOPS 1.6, except its Trade Report
    // and Trade Break messages carry 4 trailing reserved bytes; advancing by the
    // message block length skips those bytes

    foreach (i; 0 .. messageCount) {
        auto messageBlockLength = payload.read!(ushort, Endian.littleEndian);
        if (messageBlockLength == 0)
            continue;

        auto messageType = payload.peek!(ubyte, Endian.littleEndian);
        scope (exit)
            payload = payload.drop(messageBlockLength);
        switch (messageType) {
        default:
            stderr.writefln("Can't understanding message %X, skipping", messageType);
            break;
        case MessageType.priceLevelUpdateBuySide:
        case MessageType.priceLevelUpdateSellSide:
            payload.ptr.getMessage!PriceLevelUpdateMessage.serializeJson.writeln;
            break;
        case MessageType.securityEventMessage:
            payload.ptr.getMessage!SecurityEventMessage.serializeJson.writeln;
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
        case MessageType.tradeBreak:
            payload.ptr.getMessage!TradeBreakMessage.serializeJson.writeln;
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
        case MessageType.orderDelete:
            payload.ptr.getMessage!OrderDeleteMessage.serializeJson.writeln;
            break;
        case MessageType.addOrder:
            payload.ptr.getMessage!AddOrderMessage.serializeJson.writeln;
            break;
        case MessageType.orderModify:
            payload.ptr.getMessage!OrderModifyMessage.serializeJson.writeln;
            break;
        case MessageType.orderExecuted:
            payload.ptr.getMessage!OrderExecutedMessage.serializeJson.writeln;
            break;
        }
    }
}

void parsePcapNg(R)(ref R data) {
    while (true) {
        data.ensureElems(4096);
        if (data.window.count == 0)
            break;

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
            scope (exit)
                data.release(blockLength - (blockType.sizeof + blockLength.sizeof));

            auto payload = data.window.take(blockLength);

            // skip uninteresting fields
            payload = payload.drop(uint.sizeof + // interface ID
                    ulong.sizeof + // timestamp
                    uint.sizeof + // captured packet length
                    uint.sizeof // original packet length

                    );

            processFrame(payload);

            break;
        case BlockType.sectionHeader:
            // use section header to set endianness

            auto blockLength = data.read!uint;
            auto magic = data.read!uint;

            if (magic != pcapng.MagicNumber) {
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
            enforce(linkType == LinkType.ethernet,
                    "only IEEE 802.3 Ethernet link type is supported");

            // block length includes block type, and length, which have already been read
            data.release(blockLength - (blockType.sizeof + blockLength.sizeof));
        }
    }
}

void parsePcap(R)(ref R data) {
    // global header
    data.ensureElems(24);
    auto magic = data.read!uint;
    if (magic == pcap.MagicNumber.microsecondsSwapped || magic == pcap.MagicNumber.nanosecondsSwapped) {
        // swap endian
        toggleEndian;
    }

    data.release(ushort.sizeof * 2 + // version major, minor
            uint.sizeof + // time zone offset
            uint.sizeof + // timestamp accuracy
            uint.sizeof // snapshot length

            );

    auto linkType = data.read!uint;
    enforce(linkType == LinkType.ethernet,
            "only IEEE 802.3 Ethernet link type is supported");

    // packet records
    while (true) {
        data.ensureElems(4096);
        if (data.window.count < 16)
            break; // no full record header left

        data.release(uint.sizeof * 2); // timestamp seconds, fraction
        auto capturedLength = data.read!uint;
        data.release(uint.sizeof); // original packet length

        data.ensureElems(capturedLength);
        processFrame(data.window.take(capturedLength));
        data.release(capturedLength);
    }
}

void main(string[] args) {
    static immutable string[] VERSION = import(".VERSION").split;
    assert(!VERSION.empty);

    auto cmd = new Program("IEX Parser", VERSION.front).author("Jordan K. Wilson <wilsonjord@gmail.com>")
        .add(new Argument("file", "IEX TOPS file")).parse(args);

    auto data = std.io.File(cmd.arg("file"), Mode.read).refCounted.bufd.unzip;

    // detect capture file format from the first 4 bytes
    data.ensureElems(4);
    enforce(data.window.count >= 4, "file is too small to be a capture file");

    switch (data.iopPeek!uint) { // _endian defaults to bigEndian
    case BlockType.sectionHeader:
        data.parsePcapNg;
        break;
    case pcap.MagicNumber.microseconds:
    case pcap.MagicNumber.nanoseconds:
    case pcap.MagicNumber.microsecondsSwapped:
    case pcap.MagicNumber.nanosecondsSwapped:
        data.parsePcap;
        break;
    default:
        throw new Exception("unrecognised capture file format (expected pcap or pcapng)");
    }
}
