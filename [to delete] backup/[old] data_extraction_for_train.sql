with paid_orders as (
	select
		user_id,
		id as order_id,
		checked_out_at,
		row_number() over(partition by user_id order by checked_out_at) order_num
	from orders
	where deal_id is null
		and workflow_state = 'paid'
		and canceled_at is null
), canceled_orders as (
	select
		user_id,
		id as order_id,
		canceled_at,
		row_number() over(partition by user_id order by canceled_at) cancelation_num
	from orders
	where deal_id is null
		and workflow_state = 'canceled'
		and confirmed_at is not null
), user_credit_cards as (
	select 
		user_id,
		count(id) as credit_cards_num
	from credit_cards 
	where status = 'IsActive'
	group by 1 
	order by 2 desc
), orders_info as (
	select
		*,
		round(EXTRACT(epoch FROM (start_at - created_at))/3600) as creation_start_hours,
		-- Payment type
		case when payment_type = 'cash' then 1 else 0 end as cash_flg,
		case when payment_type = 'credit_card' then 1 else 0 end as credit_card_flg,
		
		-- Creation mean
		case when creation_mean = 'auto' then 1 else 0 end as auto_flg,
		case when creation_mean = 'admin' then 1 else 0 end as admin_flg,
		case when creation_mean = 'web_new_flow' then 1 else 0 end as web_flg,
		case when creation_mean = 'ios' then 1 else 0 end as ios_flg,
		
		-- Hot
		case when hot then 1 else 0 end as hot_flg,
		
		-- Additionals
		case when refrigerator='TRUE' then 1 else 0 end as refrigerator_flg,
		case when oven='TRUE' then 1 else 0 end as oven_flg,
		case when windows > 0 then 1 else 0 end as windows_fls,
		case when ironing > 0 then 1 else 0 end as ironing_flg,
		case when kitchen_cabinets='TRUE' then 1 else 0 end kitchen_cabinets_flg,
		case when tableware='TRUE' then 1 else 0 end tableware_flg,
		case when balconies > 0 then 1 else 0 end as balconies_flg,
		case when microwave='TRUE' then 1 else 0 end microwave_flg,
		case when keys_delivery='TRUE' then 1 else 0 end as keys_delivery_flg,
		
		
		-- Start DOW
		case when extract(dow from start_at) = 0 then 1 else 0 end sun_flg,
		case when extract(dow from start_at) = 1 then 1 else 0 end mon_flg,
		case when extract(dow from start_at) = 2 then 1 else 0 end tue_flg,
		case when extract(dow from start_at) = 3 then 1 else 0 end wed_flg,
		case when extract(dow from start_at) = 4 then 1 else 0 end thu_flg,
		case when extract(dow from start_at) = 5 then 1 else 0 end fri_flg,
		case when extract(dow from start_at) = 6 then 1 else 0 end sat_flg,

		-- Start Time
		case when extract(hour from start_at) < 9 then 1 else 0 end morning_slot,
		case when extract(hour from start_at) between 10 and 14 then 1 else 0 end day_slot,
		case when extract(hour from start_at) >= 15 then 1 else 0 end evening_slot,
		
		
		case when us.user_id is not null then 1 else 0 end as has_active_credit_card,
		case when o.notice is not null then 1 else 0 end as has_comment,
		case when o.subscription_id is not null then 1 else 0 end as subscription_flg,
		-- это нужно проверить
		(select coalesce(max(cancelation_num), 0) from canceled_orders as c where c.user_id = o.user_id and c.canceled_at <= least(o.start_at, o.canceled_at)) as canceled_orders_num_before,
		-- это нужно проверить
		(select coalesce(max(order_num), 0) from paid_orders as p where p.user_id = o.user_id and p.checked_out_at <= o.start_at) as paid_orders_num_before,
		case when canceled_at is not null then 1 else 0 end as canceled
	from orders as o
		left join user_credit_cards as us on (o.user_id = us.user_id)
	where confirmed_at is not null
		and start_at >= '2017-05-16'
		and start_at < '2017-05-19'
		--and date(start_at) = current_date + 2
		and deal_id is null
		and workflow_state != 'hidden'
)

    
select
	id as order_id,
	--web_id as order_id,
	--'https://qlean.ru/admin/orders/'||web_id as admin_link,
	total_cents, -- -0.27504139  0.088
	credits_cents, -- -0.0777946  -0.176
	subscription_discount_cents, -- -0.07126576 0.047
	promocode_discount_cents, -- -0.31547751
	rooms, -- 0.16816797 
	bathrooms, -- 0.07383535
	cash_flg, -- 0.84681422
	credit_card_flg, -- 1.19190939
	auto_flg, -- 0.35726044 
	admin_flg, -- -0.19933211
	web_flg, -- -0.13691376
	ios_flg, -- -0.11251496
	hot_flg, -- -0.01671453
	has_active_credit_card, -- -0.33753236
	has_comment, -- -0.08648277
	subscription_flg, -- -0.04212386
	canceled_orders_num_before, -- 0.94393635
	paid_orders_num_before, -- -1.12015689
	case when paid_orders_num_before>0 then canceled_orders_num_before / paid_orders_num_before::float else 0 end as cancelation_share,
	creation_start_hours, -- 0.05035143
	
	-- Additionals
	refrigerator_flg,
	oven_flg,
	windows_fls,
	ironing_flg,
	kitchen_cabinets_flg,
	tableware_flg,
	balconies_flg,
	microwave_flg,
	keys_delivery_flg,
	refrigerator_flg + oven_flg + windows_fls + ironing_flg + kitchen_cabinets_flg + tableware_flg + balconies_flg + microwave_flg + keys_delivery_flg as additionals_num,
	
	-- Start DOW
	case when (sun_flg + sat_flg + fri_flg) > 0 then 1 else 0 end as weekend_flg,
	--sun_flg,
	--mon_flg,
	--tue_flg,
	--wed_flg,
	--thu_flg,
	--fri_flg,
	--sat_flg,
	
	-- Start Time Slots
	morning_slot,
	day_slot,
	evening_slot
	
	, canceled
from orders_info;