import { Decimal } from 'decimal.js';
import type pg from 'pg';

export interface ExchangeRate {
  base: string;
  quote: string;
  requestedDate: string;
  observedDate: string;
  rate: string;
  source: string;
}

export class ExchangeService {
  constructor(private readonly pool: pg.Pool, private readonly fetcher: typeof fetch = fetch) {}

  async get(base: string, quote: string, date: string): Promise<ExchangeRate> {
    if (base === quote) return { base, quote, requestedDate: date, observedDate: date, rate: '1', source: 'identity' };
    const cached = await this.pool.query(`SELECT rate::text, observed_date::text AS "observedDate", source
      FROM exchange_rates WHERE base=$1 AND quote=$2 AND requested_date=$3`, [base, quote, date]);
    if (cached.rows[0]) return { base, quote, requestedDate: date, ...cached.rows[0] };
    const response = await this.fetcher(`https://api.frankfurter.dev/v2/rate/${base}/${quote}?date=${date}`, { signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error('The exchange rate provider is unavailable for this pair or date.');
    const data = await response.json() as { date?: string; base?: string; quote?: string; rate?: number };
    if (!data.date || !/^\d{4}-\d{2}-\d{2}$/.test(data.date) || data.date > date || data.base !== base || data.quote !== quote || !data.rate || !Number.isFinite(data.rate) || data.rate <= 0) {
      throw new Error('Invalid response from the exchange rate provider.');
    }
    const rate = new Decimal(data.rate).toFixed();
    await this.pool.query(`INSERT INTO exchange_rates(base,quote,requested_date,observed_date,rate,source)
      VALUES($1,$2,$3,$4,$5,'Frankfurter') ON CONFLICT DO NOTHING`, [base, quote, date, data.date, rate]);
    // Read back the winning value so simultaneous requests use the same locked observation.
    const saved = await this.pool.query(`SELECT rate::text, observed_date::text AS "observedDate", source
      FROM exchange_rates WHERE base=$1 AND quote=$2 AND requested_date=$3`, [base, quote, date]);
    return { base, quote, requestedDate: date, ...saved.rows[0] };
  }
}
