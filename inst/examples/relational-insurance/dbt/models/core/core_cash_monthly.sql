-- Aggregate transaction cash independently of the policy stock.
select
  company,
  channel,
  month,
  cast(count(*) as integer) as payment_count,
  cast(sum(cash_amount) as double) as cash_collected
from {{ source('accepted_products', 'payments') }}
group by company, channel, month
