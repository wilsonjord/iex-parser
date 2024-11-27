module iex;

import std.string;
import std.format;
import std.math;
import std.conv;
import std.datetime;
import std.bitmanip;

import asdf;

// data types used in spec
alias Long        = long;
alias Price       = long;
alias Integer     = int;
alias Byte        = ubyte;
alias String      = char[8];
alias ShortString = char[4];
alias Timestamp   = long;
alias EventTime   = uint;

// boilerplate functions
auto generateTime(T) (string fieldName) if (is(T == Timestamp) || is(T == EventTime)) {
    static if (is(T == EventTime)) {
        enum UNITS = 1;
    } else {
        enum UNITS = 1_000_000_000.0;
    }

    auto memberName = "_" ~ fieldName;

    return iq{
        @serdeIgnore $(T.stringof) $(memberName); 
        string $(fieldName)() const @property {
            real frac;
            real seconds;

            frac = modf($(memberName) / $(UNITS), seconds);
            
            auto rvalue = SysTime.fromUnixTime(seconds.to!long, UTC());
            rvalue.fracSecs = usecs((frac * 1_000_000).to!int);
            return rvalue.toISOExtString;
        }
    }.text;
}

auto generateString(T) (string fieldName) if (is(T == String) || is(T == ShortString)) {
    auto memberName = "_" ~ fieldName;

    return iq{
        @serdeIgnore $(T.stringof) $(memberName);
        auto $(fieldName)() const @property {
            return $(memberName).stripRight;
        }
    }.text;
}

auto generatePrice(string fieldName) {
    auto memberName = "_" ~ fieldName;
    
    return iq{
        @serdeIgnore Price $(memberName);
        auto $(fieldName)() const @property {
            return $(memberName) / 10_000.0;
        }
    }.text;
}

auto getMessage(T, R) (R ptr) {
    auto r = cast(T*) ptr;
    return *r;
}

enum MessageType : Byte {
    auctionInformation       = 0x41,
    securityDirectory        = 0x44,
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

struct AuctionInformationMessage {
    enum AuctionType : Byte {
        O = 0x4f,
        C = 0x43,
        I = 0x49,
        H = 0x48,
        V = 0x56
    }

    align(1):
    MessageType type;
    AuctionType auctionType;
    mixin(generateTime!Timestamp("time"));
    mixin(generateString!String("symbol"));
    Integer pairedShares;
    mixin(generatePrice("reference"));
    mixin(generatePrice("indicativeClearing"));
    Integer imbalanceShares;
    Byte imbalanceSide;
    Byte extensionNumber;
    mixin(generateTime!EventTime("scheduledTime"));
    mixin(generatePrice("clearing"));
    mixin(generatePrice("collarReference"));
    mixin(generatePrice("lowerAuctionCollar"));
    mixin(generatePrice("upperAuctionCollar"));
}

struct OfficialPriceMessage {
    enum PriceType : Byte {
        opening = 0x51,
        closing = 0x4d
    }

    align(1):
    MessageType type;
    PriceType priceType;
    mixin(generateTime!Timestamp("time"));
    mixin(generateString!String("symbol"));
    mixin(generatePrice("price"));
}

struct OperationalHaltStatusMessage {
    enum Status : Byte {
        O = 0x4f,
        N = 0x4e
    }

    align(1):
    MessageType type;
    Status operationalHaltStatus;
    mixin(generateTime!Timestamp("time"));
    mixin(generateString!String("symbol"));
}

struct QuoteUpdateMessage {
    enum MarketSessionFlag {
        regular = 0,
        prePost = 1
    }

    enum SymbolAvailabilityFlag {
        active = 0,
        notActive = 1
    }

    struct QuoteUpdateFlags {
        mixin(bitfields!(
            uint, "", 6,
            MarketSessionFlag, "marketSession", 1,
            SymbolAvailabilityFlag, "symbolAvailability", 1));
    }

    align(1):
    MessageType type;
    QuoteUpdateFlags flags;
    mixin(generateTime!Timestamp("time"));
    mixin(generateString!String("symbol"));
    Integer bidSize;
    mixin(generatePrice("bidPrice"));
    mixin(generatePrice("askPrice"));
    Integer askSize;
}

struct RetailLiquidityIndicatorMessage {
    enum Indicator : Byte {
        NA = 0x20,
        A  = 0x41,
        B  = 0x42,
        C  = 0x43
    }

    align(1):
    MessageType type;
    Indicator indicator;
    mixin(generateTime!Timestamp("time"));
    mixin(generateString!String("symbol"));
}

struct SecurityDirectoryMessage {
    enum ETPFlag {
        notETP = 0,
        ETP = 1
    }

    enum WhenIssuedFlag {
        notWhenIssued = 0,
        whenIssued = 1
    }

    enum TestSecurityFlag {
        notTest = 0,
        test = 1
    }

    struct SecurityDirectoryFlags {
        mixin(bitfields!(
            uint,             "", 5,
            ETPFlag,          "etp", 1,
            WhenIssuedFlag,   "whenIssued", 1,
            TestSecurityFlag, "testSecurity", 1));
    }

    align(1):
    MessageType type;
    SecurityDirectoryFlags flags;
    mixin(generateTime!Timestamp("time"));
    mixin(generateString!String("symbol"));
    Integer roundLotSize;
    mixin(generatePrice("adjustedPOCPrice"));
    Byte luldTier;
}

struct ShortSalePriceTestStatusMessage {
    enum Status : Byte {
        notInEffect = 0x0,
        inEffect    = 0x1
    }

    enum Detail : Byte {
        none         = 0x20,
        activated    = 0x41,
        continued    = 0x43,
        deactivated  = 0x44,
        notAvailable = 0x4e
    }

    align(1):
    MessageType type;
    Status shortSalePriceTestStatus;
    mixin(generateTime!Timestamp("time"));
    mixin(generateString!String("symbol"));
    Detail detail;
}

struct SystemEventMessage {
    enum SystemEvent : Byte {
        O = 0x4f,
        S = 0x53,
        R = 0x52,
        M = 0x4d,
        E = 0x45,
        C = 0x43
    }

    align(1):
    MessageType type;
    SystemEvent event;
    mixin(generateTime!Timestamp("time"));
}

struct TradeReportMessage {
    enum IntermarketSweepFlag {
        nonISO = 0,
        ISO    = 1
    }

    enum ExtendedHoursFlag {
        regular  = 0,
        extended = 1
    }

    enum OddLotFlag {
        roundMixed = 0,
        oddLot     = 1
    }

    enum TradeThroughExemptFlag {
        subjectToRule    = 0,
        notSubjectToRule = 1
    }

    enum SinglePriceCrossTradeFlag {
        continuousTrading = 0,
        singlePriceCross  = 1
    }

    struct SalesConditionFlags {
        mixin(bitfields!(
            uint,                      "", 3,
            SinglePriceCrossTradeFlag, "singlePriceCross", 1,
            TradeThroughExemptFlag,    "tradeThroughExempt", 1,
            OddLotFlag,                "oddLot", 1,
            ExtendedHoursFlag,         "extendedHours", 1,
            IntermarketSweepFlag,      "intermarketSweep", 1));
    }

    align(1):
    MessageType type;
    SalesConditionFlags salesConditionFlags;
    mixin(generateTime!Timestamp("time"));
    mixin(generateString!String("symbol"));
    Integer size;
    mixin(generatePrice("price"));
    Long id;
}

struct TradingStatusMessage {
    enum Status : Byte {
        H = 0x48,
        O = 0x4f,
        P = 0x50,
        T = 0x54
    }

    align(1):
    MessageType type;
    Status tradingStatus;
    mixin(generateTime!Timestamp("time"));
    mixin(generateString!String("symbol"));
    mixin(generateString!ShortString("reason"));
}
