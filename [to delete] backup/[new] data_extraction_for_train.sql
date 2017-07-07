with constants as (
	select
		'2016-01-01'::date as start_date,
		'2017-05-01'::date as end_date 
), orders_recency_info as (
	select
		o1.user_id,
		o1.id as order_id,
		count(distinct date(o2.start_at)) filter (where o2.workflow_state = 'paid' 
			and o2.checked_out_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null) as paid_all,
		count(distinct date(o2.canceled_at)) filter (where o2.workflow_state = 'canceled' 
			and o2.canceled_at < o1.start_at
			and o2.deal_id is null
			and o2.confirmed_at is not null) as canceled_all,
		count(distinct date(o2.start_at)) filter (where o2.workflow_state = 'paid' 
			and date(o1.start_at) - date(o2.checked_out_at) < 16
			and o2.deal_id is null
			and o2.confirmed_at is not null) as paid_16d,
		count(distinct date(o2.canceled_at)) filter (where o2.workflow_state = 'canceled' 
			and date(o1.start_at) - date(o2.canceled_at) < 16
			and o2.deal_id is null
			and o2.confirmed_at is not null) as canceled_16d,
		count(distinct date(o2.start_at)) filter (where o2.workflow_state = 'paid' 
			and date(o1.start_at) - date(o2.checked_out_at) < 30
			and o2.deal_id is null
			and o2.confirmed_at is not null) as paid_30d,
		count(distinct date(o2.canceled_at)) filter (where o2.workflow_state = 'canceled' 
			and date(o1.start_at) - date(o2.canceled_at) < 30
			and o2.deal_id is null
			and o2.confirmed_at is not null) as canceled_30d,
		count(distinct date(o2.start_at)) filter (where o2.workflow_state = 'paid' 
			and date(o1.start_at) - date(o2.checked_out_at) < 60
			and o2.deal_id is null
			and o2.confirmed_at is not null) as paid_60d,
		count(distinct date(o2.canceled_at)) filter (where o2.workflow_state = 'canceled' 
			and date(o1.start_at) - date(o2.canceled_at) < 60
			and o2.deal_id is null
			and o2.confirmed_at is not null) as canceled_60d
	from orders o1
		left join orders o2 on (o1.user_id = o2.user_id and o2.start_at < o1.start_at)
	where o1.deal_id is null
		and o1.confirmed_at is not null
		and o1.workflow_state in ('paid', 'canceled')
		and o1.start_at >= (select start_date from constants)
		and o1.start_at < (select end_date from constants)
		
	group by 1,2
	order by 2
), orders_general_info as (
	select
		o.id as order_id,
		o.rooms, -- ohc?
		o.bathrooms, -- ohc?
		o.total_cents,
		o.subtotal_cents,
		o.subtotal_cents - o.total_cents as discount,
		case when o.subtotal_cents != 0 then (o.subtotal_cents - o.total_cents)/o.subtotal_cents::float else 1 end as discount_prc,
		o.payment_type, -- ohc
		o.creation_mean, -- ohc
		extract(dow from start_at) as dow, -- ohc
		case when hot then 1 else 0 end as hot,
		
		-- Additionals
		case when refrigerator then 1 else 0 end as refrigerator_flg,
		case when oven then 1 else 0 end as oven_flg,
		case when windows > 0 then 1 else 0 end as windows_fls,
		case when ironing > 0 then 1 else 0 end as ironing_flg,
		case when kitchen_cabinets then 1 else 0 end kitchen_cabinets_flg,
		case when tableware then 1 else 0 end tableware_flg,
		case when balconies > 0 then 1 else 0 end as balconies_flg,
		case when microwave then 1 else 0 end microwave_flg,
		case when keys_delivery then 1 else 0 end as keys_delivery_flg,
		case when consumables_and_equipment then 1 else 0 end as consumables_flg,
		case when shower then 1 else 0 end as shower_flg,
		case when bedlinen then 1 else 0 end as bedlinen_flg,
		case when cat_litter_box > 0 then 1 else 0 end as cat_flg,
		case when lustre > 0 then 1 else 0 end as lustre_flg,
		case when wardrobe then 1 else 0 end as wardrobe_flg,
		(case when refrigerator then 1 else 0 end
			+ case when oven then 1 else 0 end
			+ case when windows > 0 then 1 else 0 end
			+ case when ironing > 0 then 1 else 0 end
			+ case when kitchen_cabinets then 1 else 0 end
			+ case when tableware then 1 else 0 end
			+ case when balconies > 0 then 1 else 0 end
			+ case when microwave then 1 else 0 end
			+ case when keys_delivery then 1 else 0 end
			+ case when consumables_and_equipment then 1 else 0 end
			+ case when shower then 1 else 0 end
			+ case when bedlinen then 1 else 0 end
			+ case when cat_litter_box > 0 then 1 else 0 end
			+ case when lustre > 0 then 1 else 0 end
			+ case when wardrobe then 1 else 0 end) as additionals_num,
		
		-- Start Time
		case when extract(hour from start_at) < 9 then 1 else 0 end morning_slot,
		case when extract(hour from start_at) between 10 and 14 then 1 else 0 end day_slot,
		case when extract(hour from start_at) >= 15 then 1 else 0 end evening_slot,
		
		o.type, -- ohc
		case when o.notice is not null then 1 else 0 end as has_comment,
		case when o.subscription_id is not null then 1 else 0 end as subscription_flg,
		a.lat,
		a.lng,
		round(EXTRACT(epoch FROM (o.start_at - o.created_at))/3600) as creation_start_hours,
		
		-- TARGET
		case when canceled_at is not null then 1 else 0 end as cancel
	from orders o
		left join addresses a on (o.address_id = a.id)
	where deal_id is null
		and confirmed_at is not null
		and workflow_state in ('paid', 'canceled')
		and start_at >= (select start_date from constants)
		and start_at < (select end_date from constants)
), order_deltas as (
	select 
		model_id as order_id,
		json_array_elements(object)->>'name' as field_name,
		json_array_elements(object)->>'object'  as field_value,
		created_at
	from deltas
	where model_type='Order'
		and model_id in (select order_id from orders_general_info)
), order_shifts as (
	select
		order_id,
		count(order_id)-1 as shifts_num
	from order_deltas
	where field_name = 'start_at'
	group by 1
)


select 
	g.*,
	r.paid_all,
	r.canceled_all,
	case when r.canceled_all != 0  then r.canceled_all/(r.paid_all + r.canceled_all)::float else 0 end as canceled_all_share,
	paid_16d,
	canceled_16d,
	case when canceled_16d != 0 then canceled_16d/(paid_16d + canceled_16d)::float else 0 end as canceled_16d_share,
	paid_30d,
	canceled_30d,
	case when canceled_30d != 0 then canceled_30d/(paid_30d + canceled_30d)::float else 0 end as canceled_30d_share,
	paid_60d,
	canceled_60d,
	case when canceled_60d != 0 then canceled_60d/(paid_60d + canceled_60d)::float else 0 end as canceled_60d_share,
	shifts_num -- fill_na
	
from orders_general_info g
	left join orders_recency_info r on (g.order_id = r.order_id)
	left join order_shifts s on (g.order_id = s.order_id)
where creation_mean is not null;