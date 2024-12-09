module iex;

import std.string;
import std.format;
import std.math;
import std.conv;
import std.datetime;
import std.bitmanip;

import mir.ser.json;
import mir.small_string;

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
    systemEvent              = 0x53,
    tradeReport              = 0x54,
    officialPrice            = 0x58
}

// IEX messages

auto getMessage(T, R) (R ptr) {
    auto r = cast(T*) ptr;
    return *r;
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
    Byte imbalanceSide;
    Byte extensionNumber;
    EventTime scheduleAuctionTime;
    Price auctionBookClearingPrice;
    Price collarReferencePrice;
    Price lowerAuctionCollar;
    Price upperAuctionCollar;
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

struct OperationalHaltStatusMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte operationalHaltStatus;
    Timestamp timestamp;
    String symbol;
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

struct RetailLiquidityIndicatorMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte retailLiquidityIndicator;

    Timestamp timestamp;
    String symbol;
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

struct SecurityEventMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte securityEvent;
    Timestamp timestamp;
    String symbol;
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

struct TradingStatusMessage {
    align(1):
    MessageType messageType;
    @serdeProxy!char
    Byte tradingStatus;
    Timestamp timestamp;
    String symbol;
    ShortString reason;
}
