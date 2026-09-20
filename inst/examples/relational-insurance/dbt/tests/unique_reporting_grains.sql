select 'policy_monthly' as model, company, channel, month
from {{ ref('core_policy_monthly') }}
group by company, channel, month having count(*) <> 1
union all
select 'cash_monthly' as model, company, channel, month
from {{ ref('core_cash_monthly') }}
group by company, channel, month having count(*) <> 1
union all
select 'monthly_performance' as model, company, channel, month
from {{ ref('monthly_performance') }}
group by company, channel, month having count(*) <> 1
