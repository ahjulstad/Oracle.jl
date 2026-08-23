# Conversions between Oracle INTERVAL values and `Dates` periods.

const YEAR_MONTH_PERIODS = Union{Dates.Year, Dates.Quarter, Dates.Month}
const DAY_SECOND_PERIODS = Union{Dates.Week, Dates.Day, Dates.Hour, Dates.Minute,
                                 Dates.Second, Dates.Millisecond,
                                 Dates.Microsecond, Dates.Nanosecond}

is_year_month_period(p::Dates.Period) = p isa YEAR_MONTH_PERIODS
is_year_month_period(p::Dates.CompoundPeriod) =
    !isempty(p.periods) && all(is_year_month_period, p.periods)

periods(p::Dates.Period) = (p,)
periods(p::Dates.CompoundPeriod) = p.periods

function OraIntervalDS(p::Union{Dates.Period, Dates.CompoundPeriod})
    total = Dates.Nanosecond(0)
    for part in periods(p)
        part isa DAY_SECOND_PERIODS ||
            throw(ArgumentError("`$part` cannot be expressed as an INTERVAL DAY TO SECOND."))
        total += Dates.Nanosecond(part)
    end
    ns = Dates.value(total)
    sign = ns < 0 ? -1 : 1
    ns = abs(ns)
    days, ns = divrem(ns, 86_400_000_000_000)
    hours, ns = divrem(ns, 3_600_000_000_000)
    minutes, ns = divrem(ns, 60_000_000_000)
    seconds, fseconds = divrem(ns, 1_000_000_000)
    return OraIntervalDS(sign * days, sign * hours, sign * minutes, sign * seconds, sign * fseconds)
end

function OraIntervalYM(p::Union{Dates.Period, Dates.CompoundPeriod})
    total = 0
    for part in periods(p)
        part isa YEAR_MONTH_PERIODS ||
            throw(ArgumentError("`$part` cannot be expressed as an INTERVAL YEAR TO MONTH."))
        total += Dates.value(Dates.Month(part))
    end
    years, months = divrem(total, 12)
    return OraIntervalYM(years, months)
end

function parse_interval_ds(iv::OraIntervalDS) :: Dates.CompoundPeriod
    return Dates.canonicalize(Dates.CompoundPeriod(Dates.Period[
        Dates.Day(iv.days),
        Dates.Hour(iv.hours),
        Dates.Minute(iv.minutes),
        Dates.Second(iv.seconds),
        Dates.Nanosecond(iv.fseconds)]))
end

function parse_interval_ym(iv::OraIntervalYM) :: Dates.CompoundPeriod
    return Dates.canonicalize(Dates.CompoundPeriod(Dates.Period[
        Dates.Year(iv.years),
        Dates.Month(iv.months)]))
end
