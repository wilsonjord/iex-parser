module iex;

import std.string;
import std.format;
import std.math;
import std.conv;
import std.datetime;
import std.bitmanip;

import mir.ser.json;
import mir.small_string;

debug import std.stdio;
debug import dshould;

// IEX data types
alias Long        = long;
alias Integer     = int;
alias Byte        = ubyte;
alias String      = SmallStringType!8;
alias ShortString = SmallStringType!4;

@serdeProxy!(const(char)[])
struct SmallStringType(int T) {
    SmallString!T str;

    auto toString() const @safe {
        return str[].stripRight;
    }
}

auto convertIexTime(long time) {
    real frac;
    real seconds;

    frac = modf(time / 1_000_000_000.0, seconds); // nanoseconds

    auto rvalue = SysTime.fromUnixTime(seconds.to!long, UTC());
    rvalue.fracSecs = usecs((frac * 1_000_000).to!int);

    return rvalue.toISOExtString;
}

@serdeProxy!(const(char)[])
struct Timestamp {
    long time;

    auto toString() const @safe {
        return time.convertIexTime;
    }
}

@serdeProxy!(const(char)[])
struct EventTime {
    uint time;

    auto toString() const @safe {
        return SysTime.fromUnixTime(time.to!long, UTC()).toISOExtString;
    }
}

@serdeProxy!double
struct Price {
    long price;

    double opCast(T : double)() const {
        return price / 10_000.0;
    }
}

@serdeProxy!char
enum MessageType : Byte {
    priceLevelUpdateSellSide = 0x35,
    priceLevelUpdateBuySide  = 0x38,
    auctionInformation       = 0x41,
    securityDirectory        = 0x44,
    securityEventMessage     = 0x45,
    tradingStatus            = 0x48,
    retailLiquidityIndicator = 0x49,
    operationalHaltStatus    = 0x4f,
    shortSalePriceTestStatus = 0x50,
    quoteUpdate              = 0x51,
    orderDelete              = 0x52,
    systemEvent              = 0x53,
    tradeReport              = 0x54,
    officialPrice            = 0x58,
    addOrder                 = 0x61
}

// IEX messages

auto getMessage(T, R) (R ptr) {
    auto r = cast(T*) ptr;
    return *r;
}

struct AddOrderMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte side;
    Timestamp timestamp;
    String symbol;
    Long orderId;
    Integer size;
    Price price;
}

unittest {
    import std.json;
    auto data = hexString!"6138b28fa5a0ab866d145a49455854202020968f06000000000064000000241d0f0000000000";

    auto message = getMessage!AddOrderMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("a");
    message["side"].get!string.should.equal("8");

    // NOTE: timestamp skipped, specification contains a bad example value for timestamp

    message["symbol"].get!string.should.equal("ZIEXT");
    message["orderId"].get!long.should.equal(429974);
    message["price"].get!double.should.equal(99.05);
}

struct AuctionInformationMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte auctionType;
    Timestamp timestamp;
    String symbol;
    Integer pairedShares;
    Price referencePrice;
    Price indicativeClearingPrice;
    Integer imbalanceShares;
    @serdeProxy!char
    Byte imbalanceSide;
    Byte extensionNumber;
    EventTime scheduledAuctionTime;
    Price auctionBookClearingPrice;
    Price collarReferencePrice;
    Price lowerAuctionCollar;
    Price upperAuctionCollar;
}

unittest {
    import std.json;
    auto data = hexString!"
        4143ddc7f09a1a3ab6145a4945585420
        2020a0860100241d0f0000000000181f
        0f000000000010270000420080e6f458
        0c210f0000000000c01c0f0000000000
        a4990d0000000000dc9f100000000000";

    auto message = getMessage!AuctionInformationMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("A");
    message["auctionType"].get!string.should.equal("C");
    message["timestamp"].get!string.should.equal("2017-04-17T15:50:12.462929Z");
    message["symbol"].get!string.should.equal("ZIEXT");
    message["pairedShares"].get!int.should.equal(100_000);
    message["referencePrice"].get!double.should.equal(99.05);
    message["indicativeClearingPrice"].get!double.should.equal(99.10);
    message["imbalanceShares"].get!int.should.equal(10_000);
    message["imbalanceSide"].get!string.should.equal("B");
    message["extensionNumber"].get!int.should.equal(0);
    message["scheduledAuctionTime"].get!string.should.equal("2017-04-17T16:00:00Z");
    message["auctionBookClearingPrice"].get!double.should.equal(99.15);
    message["collarReferencePrice"].get!double.should.equal(99.04);
    message["lowerAuctionCollar"].get!double.should.equal(89.13);
    message["upperAuctionCollar"].get!double.should.equal(108.95);
}

struct OfficialPriceMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte priceType;
    Timestamp timestamp;
    String symbol;
    Price officialPrice;
}

unittest {
    import std.json;
    auto data = hexString!"585100f0302a5b25b6145a49455854202020241d0f0000000000";
    auto message = getMessage!OfficialPriceMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("X");
    message["priceType"].get!string.should.equal("Q");
    message["timestamp"].get!string.should.equal(SysTime(DateTime(2017, 4, 17, 9, 30, 0), UTC()).toISOExtString);
    message["symbol"].get!string.should.equal("ZIEXT");
    message["officialPrice"].get!double.should.equal(99.05);
}

struct OperationalHaltStatusMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte operationalHaltStatus;
    Timestamp timestamp;
    String symbol;
}

unittest {
    import std.json;
    auto data = hexString!"4f4fac63c02096866d145a49455854202020";
    auto message = getMessage!OperationalHaltStatusMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("O");
    message["operationalHaltStatus"].get!string.should.equal("O");

    // NOTE: timestamp skipped, specification contains a bad example value for timestamp

    message["symbol"].get!string.should.equal("ZIEXT");
}

struct OrderDeleteMessage {
    align(1):
    MessageType messageType;
    Byte reserved;
    Timestamp timestamp;
    String symbol;
    Long orderIdReference;
}

unittest {
    import std.json;
    auto data = hexString!"5200b28fa5a0ab866d145a49455854202020968f060000000000";
    auto message = getMessage!OrderDeleteMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("R");

    // NOTE: timestamp skipped, specification contains a bad example value for timestamp

    message["symbol"].get!string.should.equal("ZIEXT");
    message["orderIdReference"].get!long.should.equal(429974);
}

struct PriceLevelUpdateMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!uint
    Byte eventFlags;
    Timestamp timestamp;
    String symbol;
    Integer size;
    Price price;
}

unittest {
    import std.json;
    auto data = hexString!"3801ac63c02096866d145a49455854202020e4250000241d0f0000000000";
    auto message = getMessage!PriceLevelUpdateMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("8");
    message["eventFlags"].get!int.should.equal(1); // event processing complete

    // NOTE: timestamp skipped, specification contains a bad example value for timestamp

    message["symbol"].get!string.should.equal("ZIEXT");
    message["size"].get!int.should.equal(9700);
    message["price"].get!double.should.equal(99.05);
}

struct QuoteUpdateMessage {
    struct QuoteUpdateFlags {
        mixin(bitfields!(
            uint,  "", 6,
            ubyte, "marketSession", 1,
            ubyte, "symbolAvailability", 1));
    }

    align(1):
    MessageType messageType;
    QuoteUpdateFlags flags;
    Timestamp timestamp;
    String symbol;
    Integer bidSize;
    Price bidPrice;
    Price askPrice;
    Integer askSize;
}

unittest {
    import std.json;
    auto data = hexString!"5100ac63c02096866d145A49455854202020e4250000241d0f0000000000ec1d0f0000000000e8030000";
    auto message = getMessage!QuoteUpdateMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("Q");
    message["flags"]["marketSession"].get!int.should.equal(0); // regular market session
    message["flags"]["symbolAvailability"].get!int.should.equal(0); // symbol is active

    // NOTE: timestamp skipped, specification contains a bad example value for timestamp

    message["symbol"].get!string.should.equal("ZIEXT");
    message["bidSize"].get!int.should.equal(9700);
    message["bidPrice"].get!double.should.equal(99.05);
    message["askPrice"].get!double.should.equal(99.07);
    message["askSize"].get!int.should.equal(1000);
}

struct RetailLiquidityIndicatorMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte retailLiquidityIndicator;

    Timestamp timestamp;
    String symbol;
}

unittest {
    import std.json;
    auto data = hexString!"4941ac63c02096866d145a49455854202020";
    auto message = getMessage!RetailLiquidityIndicatorMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("I");
    message["retailLiquidityIndicator"].get!string.should.equal("A");

    // NOTE: timestamp skipped, specification contains a bad example value for timestamp

    message["symbol"].get!string.should.equal("ZIEXT");
}

struct SecurityDirectoryMessage {
    struct SecurityDirectoryFlags {
        mixin(bitfields!(
            uint, "", 5,
            ubyte, "ETP", 1,
            ubyte, "whenIssued", 1,
            ubyte, "testSecurity", 1));
    }

    align(1):
    MessageType messageType;
    SecurityDirectoryFlags flags;
    Timestamp timestamp;
    String symbol;
    Integer roundLotSize;
    Price adjustedPOCPrice;
    @serdeProxy!uint
    Byte luldTier;
}

unittest {
    import std.json;
    auto data = hexString!"44800020897b5a1fb6145a4945585420202064000000241d0f000000000001";
    auto message = getMessage!SecurityDirectoryMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("D");
    message["flags"]["testSecurity"].get!int.should.equal(1); // test security
    message["flags"]["ETP"].get!int.should.equal(0); // not an ETP
    message["flags"]["whenIssued"].get!int.should.equal(0); // not a When Issued security
    message["timestamp"].get!string.should.equal(SysTime(DateTime(2017, 4, 17, 7, 40, 0), UTC()).toISOExtString);
    message["symbol"].get!string.should.equal("ZIEXT");
    message["roundLotSize"].get!int.should.equal(100);
    message["adjustedPOCPrice"].get!double.should.equal(99.05);
    message["luldTier"].get!int.should.equal(1);
}

struct SecurityEventMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte securityEvent;
    Timestamp timestamp;
    String symbol;
}

unittest {
    import std.json;
    auto data = hexString!"454f00f0302a5b25b6145a49455854202020";
    auto message = getMessage!SecurityEventMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("E");
    message["securityEvent"].get!string.should.equal("O");
    message["timestamp"].get!string.should.equal(SysTime(DateTime(2017, 4, 17, 9, 30, 0), UTC()).toISOExtString);
    message["symbol"].get!string.should.equal("ZIEXT");
}

struct ShortSalePriceTestStatusMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!uint
    Byte shortSalePriceTestStatus;
    Timestamp timestamp;
    String symbol;
    @serdeProxy!char
    Byte detail;
}

unittest {
    import std.json;
    auto data = hexString!"5001ac63c02096866d145a4945585420202041";
    auto message = getMessage!ShortSalePriceTestStatusMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("P");
    message["shortSalePriceTestStatus"].get!int.should.equal(1);

    // NOTE: timestamp skipped, specification contains a bad example value for timestamp

    message["symbol"].get!string.should.equal("ZIEXT");
    message["detail"].get!string.should.equal("A");
}

struct SystemEventMessage {
    enum SystemEvent : Byte {
        startMessages = 0x4f,
        startSystemHours = 0x53,
        startRegularHours = 0x52,
        endRegularHours = 0x4d,
        endSystemHours = 0x45,
        endMessages = 0x43
    }

    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte systemEvent;
    Timestamp timestamp;
}

unittest {
    import std.json;
    auto data = hexString!"534500a09997e93db614";
    auto message = getMessage!SystemEventMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("S");
    message["systemEvent"].get!string.should.equal("E");
    message["timestamp"].get!string.should.equal(SysTime(DateTime(2017, 4, 17, 17, 0, 0), UTC()).toISOExtString);
}

struct TradeReportMessage {
    struct SalesConditionFlags {
        mixin(bitfields!(
            uint, "", 3,
            uint, "singlePriceCross", 1,
            uint, "tradeThroughExempt", 1,
            uint, "oddLot", 1,
            uint, "extendedHours", 1,
            uint, "intermarketSweep", 1));
    }

    align(1):
    MessageType messageType;
    SalesConditionFlags saleConditionFlags;
    Timestamp timestamp;

    String symbol;
    Integer size;
    Price price;
    Long tradeId;
}

unittest {
    import std.json;
    auto data = hexString!"5400c3dff705a2866d145A4945585420202064000000241d0f0000000000968f060000000000";
    auto message = getMessage!TradeReportMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("T");
    message["saleConditionFlags"]["intermarketSweep"].get!int.should.equal(0); // non-ISO
    message["saleConditionFlags"]["extendedHours"].get!int.should.equal(0); // regular market session
    message["saleConditionFlags"]["oddLot"].get!int.should.equal(0); // round or mixed lot
    message["saleConditionFlags"]["tradeThroughExempt"].get!int.should.equal(0); // trade is subject to Rule 611
    message["saleConditionFlags"]["singlePriceCross"].get!int.should.equal(0); // execution during continuous trading

    // NOTE: timestamp skipped, specification contains a bad example value for timestamp

    message["symbol"].get!string.should.equal("ZIEXT");
    message["price"].get!double.should.equal(99.05);
    message["tradeId"].get!long.should.equal(429974);
}

struct TradingStatusMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte tradingStatus;
    Timestamp timestamp;
    String symbol;
    ShortString reason;
}

unittest {
    import std.json;
    auto data = hexString!"4848ac63c02096866d145a4945585420202054312020";
    auto message = getMessage!TradingStatusMessage(data).serializeJson.parseJSON;

    message["messageType"].get!string.should.equal("H");
    message["tradingStatus"].get!string.should.equal("H");

    // NOTE: timestamp skipped, specification contains a bad example value for timestamp

    message["symbol"].get!string.should.equal("ZIEXT");
    message["reason"].get!string.should.equal("T1");
}
