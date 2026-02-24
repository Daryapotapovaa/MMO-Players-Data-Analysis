/* Часть 1. Разработка витрины данных
 * Напишите ниже запрос для создания витрины данных
*/
-- Найдем три региона с наибольшим количеством заказов
WITH top_regions AS (
	SELECT region
	FROM ds_ecom.users
	GROUP BY region
	ORDER BY COUNT(buyer_id) DESC
	LIMIT 3
),
-- Соберем информацию о первом платеже, промокодах и рассрочках для каждого заказа
orders_payment_info AS (
	SELECT 
		o.order_id,
		first_pay.payment_type AS first_payment_type,
		COALESCE(promo_used, 0) AS promo_used,
		COALESCE(installment_used, 0) AS installment_used
	FROM ds_ecom.orders AS o
	LEFT JOIN (
	-- Найдем тип первой оплаты для каждого заказа
		SELECT order_id, payment_type
		FROM ds_ecom.order_payments
		WHERE payment_sequential = 1
	) AS first_pay USING(order_id)
	LEFT JOIN (
	-- Найдем заказы, при оплате которых использовались промокоды
		SELECT
			DISTINCT order_id,
			1 AS promo_used
		FROM ds_ecom.order_payments
		WHERE payment_type = 'промокод'
	) AS promo_orders USING(order_id)
	LEFT JOIN (
	-- Найдем заказы, при оплате которых использовалась рассрочка
		SELECT
			DISTINCT order_id,
			1 AS installment_used
		FROM ds_ecom.order_payments
		WHERE payment_installments > 1
	) AS installment_orders USING(order_id)
),
-- Найдем суммарную и среднюю стоимость доставленных заказов для каждого пользователя
orders_cost_info AS (
	SELECT
		u.user_id,
		u.region,
		SUM(oc.order_cost) AS total_order_costs,
		AVG(oc.order_cost) AS avg_order_cost
	FROM ds_ecom.users AS u
	RIGHT JOIN (
	-- Найдем стоимость каждого доставленного заказа
		SELECT 
			o.buyer_id,
			o.order_id,
			SUM(oi.price) + SUM(oi.delivery_cost) AS order_cost
		FROM ds_ecom.orders AS o
		LEFT JOIN ds_ecom.order_items AS oi USING(order_id)
		WHERE o.order_status = 'Доставлено'
		GROUP BY o.buyer_id, o.order_id
	) AS oc USING(buyer_id)
	GROUP BY u.user_id, u.region
),
-- Найдем количество отмененных заказов для каждого пользователя
canceled_orders_info AS (
	SELECT
		u.user_id,
		u.region,
		COUNT(u.buyer_id) AS num_canceled_orders
	FROM ds_ecom.users AS u
	LEFT JOIN ds_ecom.orders AS o ON u.buyer_id = o.buyer_id
	WHERE o.order_status = 'Отменено'
	GROUP BY u.user_id, u.region
),
-- Найдем среднюю оценку, которую пользователь ставит своим заказам
orders_rewiew_info AS (
	SELECT
		u.user_id,
		u.region,
		AVG(avg_review_score) AS avg_order_rating,
		COUNT(DISTINCT order_id) AS num_orders_with_rating
	FROM ds_ecom.users AS u
	RIGHT JOIN (
	-- Найдем среднюю оценку для каждого заказа
		SELECT 
			r.order_id,
			o.buyer_id,
			AVG(CASE WHEN review_score >= 10 THEN review_score / 10 ELSE review_score END) AS avg_review_score
		FROM ds_ecom.order_reviews AS r
		LEFT JOIN ds_ecom.orders AS o USING(order_id)
		WHERE o.order_status IN ('Доставлено', 'Отменено')
		GROUP BY r.order_id, o.buyer_id
	) AS avg_score USING(buyer_id)
	GROUP BY u.user_id, u.region
)
-- Соберем полученные данные в единую витрину, а также найдем даты первого и последнего заказа, общее количество заказов и бинарные поля таблицы
SELECT
	u.user_id,
	u.region,
	MIN(o.order_purchase_ts) AS first_order_ts,
	MAX(o.order_purchase_ts) AS last_order_ts,
	MAX(o.order_purchase_ts) - MIN(o.order_purchase_ts) AS lifetime,
	COUNT(o.buyer_id) AS total_orders,
	ori.avg_order_rating AS avg_order_rating,
	COALESCE(ori.num_orders_with_rating, 0) AS num_orders_with_rating,
	COALESCE(coi.num_canceled_orders, 0) AS num_canceled_orders,
	COALESCE(coi.num_canceled_orders, 0) / COUNT(o.buyer_id)::NUMERIC * 100 AS canceled_orders_ratio,
	COALESCE(oci.total_order_costs, 0) AS total_order_costs,
	COALESCE(oci.avg_order_cost, 0) AS avg_order_cost,
	SUM(opi.installment_used) AS num_installment_orders,
	SUM(opi.promo_used) AS num_orders_with_promo,
	CASE WHEN SUM(CASE WHEN opi.first_payment_type = 'денежный перевод' THEN 1 ELSE 0 END) >= 1 THEN 1
		 ELSE 0
	END AS used_money_transfer,
	CASE WHEN SUM(opi.installment_used) >= 1 THEN 1
		 ELSE 0
	END AS used_installments,
	CASE WHEN COALESCE(coi.num_canceled_orders, 0) > 0 THEN 1
		 ELSE 0
	END AS used_cancel
FROM ds_ecom.users AS u
LEFT JOIN ds_ecom.orders AS o USING(buyer_id)
LEFT JOIN orders_payment_info AS opi USING(order_id)
LEFT JOIN orders_cost_info AS oci USING(user_id, region)
LEFT JOIN canceled_orders_info AS coi USING(user_id, region)
LEFT JOIN orders_rewiew_info AS ori USING(user_id, region) 
WHERE u.region IN (SELECT * FROM top_regions) AND o.order_status IN ('Доставлено', 'Отменено')
GROUP BY u.user_id, u.region, ori.avg_order_rating, ori.num_orders_with_rating, coi.num_canceled_orders, oci.total_order_costs, oci.avg_order_cost
ORDER BY total_orders DESC;



/* Часть 2. Решение ad hoc задач
 * Для каждой задачи напишите отдельный запрос.
 * После каждой задачи оставьте краткий комментарий с выводами по полученным результатам.
*/

/* Задача 1. Сегментация пользователей 
 * Разделите пользователей на группы по количеству совершённых ими заказов.
 * Подсчитайте для каждой группы общее количество пользователей,
 * среднее количество заказов, среднюю стоимость заказа.
 * 
 * Выделите такие сегменты:
 * - 1 заказ — сегмент 1 заказ
 * - от 2 до 5 заказов — сегмент 2-5 заказов
 * - от 6 до 10 заказов — сегмент 6-10 заказов
 * - 11 и более заказов — сегмент 11 и более заказов
*/

-- Проведем сегментацию пользователей, предварительно объединив их заказы, сделанные в разных регионах, 
--                                            чтобы пользователь мог находиться только в одном сегменте
SELECT
	CASE WHEN total_orders = 1 THEN '1 заказ'
		 WHEN total_orders <= 5 THEN '2-5 заказов'
		 WHEN total_orders <= 10 THEN '6-10 заказов'
		 ELSE '11 и более заказов'
	END AS users_segment,
	COUNT(user_id) AS users_count,
	AVG(total_orders) AS avg_orders_count,
	SUM(total_order_costs) / SUM(total_orders)::NUMERIC AS avg_order_cost
FROM (
	SELECT
		user_id,
		SUM(total_orders) AS total_orders,
		SUM(total_order_costs) AS total_order_costs
	FROM ds_ecom.product_user_features
	GROUP BY user_id
) AS u
GROUP BY users_segment
ORDER BY users_count;

/* По результатам задачи 1 можно сделать вывод о том, что большинство пользователей (60452 человека) принадлежит сегменту "1 заказ".
 * При этом количество пользователей, сделавших более 5 заказов составляет 6 человек. 
 * Это говорит о том, что компании необходимо активно привлекать клиентов из сегмента "1 заказ" для совершения последующих покупок.
 * Самое высокое значение средней стоимости одного заказа принадлежит сегменту "1 заказ". Затем значение убывает по мере увеличения заказов в сегментах.
*/


/* Задача 2. Ранжирование пользователей 
 * Отсортируйте пользователей, сделавших 3 заказа и более, по убыванию среднего чека покупки.  
 * Выведите 15 пользователей с самым большим средним чеком среди указанной группы.
*/

-- Выведем 15 пользователей с самым большим средним чеком среди покупателей с 3 и более заказами, 
-- предварительно объединив их заказы, сделанные в разных регионах, чтобы пользователь встречался в списке только один раз
SELECT
	user_id,
	SUM(total_orders) AS orders_count,
	ROUND(SUM(total_order_costs) / SUM(total_orders)::NUMERIC, 3) AS avg_order_cost
FROM ds_ecom.product_user_features
GROUP BY user_id
HAVING SUM(total_orders) >= 3
ORDER BY avg_order_cost DESC
LIMIT 15;

/* По результатам задачи 2 можно сделать вывод о том, что среди пользователей, совершивших 3 и более заказов, 
 * наибольший средний чек одной покупки составляет 14717. 
 * Такое значение принадлежит пользователю с тремя заказами.
*/


/* Задача 3. Статистика по регионам. 
 * Для каждого региона подсчитайте:
 * - общее число клиентов и заказов;
 * - среднюю стоимость одного заказа;
 * - долю заказов, которые были куплены в рассрочку;
 * - долю заказов, которые были куплены с использованием промокодов;
 * - долю пользователей, совершивших отмену заказа хотя бы один раз.
*/

-- Проведем группировку по регионам и подсчитаем необходимые значения
SELECT 
	region,
	COUNT(user_id) AS users_count,
	SUM(total_orders) AS total_orders_count,
	SUM(total_order_costs) / SUM(total_orders)::NUMERIC AS avg_order_cost,
	SUM(num_installment_orders) / SUM(total_orders)::NUMERIC * 100 AS installment_orders_perc,
	SUM(num_orders_with_promo) / SUM(total_orders)::NUMERIC * 100 AS promo_orders_perc,
	SUM(used_cancel) / COUNT(user_id)::NUMERIC * 100 AS users_with_canceled_orders_perc
FROM ds_ecom.product_user_features
GROUP BY region;

/* По результатам задачи 3 можно сделать вывод о том, что Москва самый популярный регион по количеству пользователей и заказов.
 * Также в этом регионе наибольшая доля пользователей, отменивших заказ хотя бы раз - 0,6%, и наименьшая доля заказов в рассрочку.
 * Наименьший показатель по количеству пользователей и заказов принадлежит Новосибирской области. При этом в регионе реже всего отменяют заказы.
 * Наибольшая средняя стоимость заказа, а также доля заказов в рассрочку и с использованием промокодов принадлежит второму по популярности региону - Санкт-Петербургу.
*/


/* Задача 4. Активность пользователей по первому месяцу заказа в 2023 году
 * Разбейте пользователей на группы в зависимости от того, в какой месяц 2023 года они совершили первый заказ.
 * Для каждой группы посчитайте:
 * - общее количество клиентов, число заказов и среднюю стоимость одного заказа;
 * - средний рейтинг заказа;
 * - долю пользователей, использующих денежные переводы при оплате;
 * - среднюю продолжительность активности пользователя.
*/

-- Разделим пользователей на группы в зависимости от того, в какой месяц 2023 года они совершили первый заказ и подсчитаем необходимые значения,
-- предварительно объединив их заказы, сделанные в разных регионах, чтобы пользователь находился только в одном из месяцов
SELECT
	DATE_TRUNC('month', u.first_order_ts) AS first_order_month,
	COUNT(u.user_id) AS users_count,
	SUM(u.total_orders) AS total_orders_count,
	SUM(u.total_order_costs) / SUM(u.total_orders)::NUMERIC AS avg_order_cost,
	SUM(u.avg_order_rating) / COUNT(u.user_id)::NUMERIC AS avg_order_rating,
	SUM(u.used_money_transfer) / COUNT(u.user_id)::NUMERIC * 100 AS used_money_transfer_perc,
	AVG(u.lifetime) AS avg_user_lifetime
FROM (
	SELECT
		user_id,
		MIN(first_order_ts) AS first_order_ts,
		MAX(last_order_ts) AS last_order_ts,
		MAX(last_order_ts) - MIN(first_order_ts) AS lifetime,
		SUM(total_orders) AS total_orders,
		SUM(total_order_costs) AS total_order_costs,
		SUM(num_orders_with_rating) AS num_orders_with_rating,
		AVG(avg_order_rating) AS avg_order_rating,
		CASE WHEN SUM(used_money_transfer) > 0 THEN 1 ELSE 0 END AS used_money_transfer
	FROM ds_ecom.product_user_features
	GROUP BY user_id
) AS u
WHERE EXTRACT(YEAR FROM u.first_order_ts) = 2023
GROUP BY DATE_TRUNC('month', u.first_order_ts);

/* По результатам задачи 4 можно сделать вывод о том, что данные за первый месяц 2023 года могут быть не полными. 
 * Об этом свидетельстыует то, что количество пользователей и заказов более, чем в два раза меньше, чем в любой другой месяц.
 * Самый многочисленный месяц по присоединившимся к сервису пользователям - ноябрь.
 * Наиболее часто денежными переводами пользуются покупатнли, совершившие первый заказ в марте 2023 года.
 * Средняя продолжительность активности пользователей снижается с каждым месяцем, что напрямую связано с тем, когда пользователь совершил первый заказ. 
*/
