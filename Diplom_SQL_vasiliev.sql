--Q В каких городах больше одного аэропорта?
--A сгруппировал таблицу аэропортов по городу, подсчитал кол-во аэропортов в каждом и отобрал только те, где больше 1 
-- так же вывел кол-во аропортов в данных городах, так как это досточно логичный вопрос. 

select a.city, count(a.airport_code) number_of_airports
from airports a 
group by a.city 
having count(a.airport_code)>1

--Q В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета?
--A сделал запрос с поиском кода самолета имеющим наибольшую дальность полета,
-- затем из таблицы перелетов выбрал те аэропорты, где совершаются рейсы на данном самолете
-- distinct для того что бы отобрать только уникальные названия

select distinct f.departure_airport
from flights f
where f.aircraft_code = (
	select a.aircraft_code
	from aircrafts a 
	order by a."range" desc 
	limit 1)
	
--Q Вывести 10 рейсов с максимальным временем задержки вылета
--A добавил колонку со временем задержки рейса для тех перелетов, которые уже прошли (есть фактическое время вылета)

select *
from flights f 
where f.actual_departure is not null 
order by (f.actual_departure - f.scheduled_departure) desc
limit 10

--Q Были ли брони, по которым не были получены посадочные талоны?
--A в одной брони может быть несколько билетов, по этому используем distinct 
-- если нет посадочного талона, то в столбце boarding_no будет значение null
select distinct t.book_ref
from tickets t 
left join boarding_passes bp on t.ticket_no = bp.ticket_no 
where bp.boarding_no is null

select distinct t.book_ref, 
	case
		when bp.boarding_no is null then 'Да, есть брони без посадочных билетов'
		else 'Нет'
	end
from tickets t 
left join boarding_passes bp on t.ticket_no = bp.ticket_no 

--Q Найдите свободные места для каждого рейса, их % отношение к общему количеству мест в самолете.
-- Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого аэропорта 
-- на каждый день. Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело 
-- из данного аэропорта на этом или более ранних рейсах за день.
--A % свободных мест вычисляется по стандартной формуле. из общего числа мест вычитаем кол-во занятых, делим на общее число и * 100
-- сделал окно по аэропорту и фактической дате вылета, затем сортирую по дате

select f.flight_no, f.departure_airport, f.actual_departure ,
	round((count(s.seat_no)-count(bp.seat_no))::numeric/count(s.seat_no),2)*100 "free seats in %",
	count(bp.seat_no) "pass on boar",
	sum(count(bp.seat_no)) over (partition by f.departure_airport, date(f.actual_departure) order by f.actual_departure) "passengerse"
from flights f 
left join seats s on s.aircraft_code = f.aircraft_code 
left join boarding_passes bp on f.flight_id = bp.flight_id and bp.seat_no = s.seat_no 
group by f.flight_id, f.departure_airport

--Q Найдите процентное соотношение перелетов по типам самолетов от общего количества.
--A в подзапросе подсчитал общее число рейсов
-- затем группируем таблицу по коду самолета, считаем кол-во рейсов каждым типом, переводим в формат numeric,
-- что бы получить дробное число и округляем до 2 знака после запятой 

select f.aircraft_code, round(count(f.flight_id)::numeric/(select count(f2.flight_id) from flights f2),2)*100 as "% of flights"
from flights f 
group by f.aircraft_code 

--Q Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета?
--A в первом cte отбираю перелеты бизнес класса и их минимальную стоимость
-- во втором cte тоже самое, но для эконом класса
-- соединяют оба сте через left join (что бы избавиться от рейсов где только эконом)
--добавляю оставшуюся информацию по перелету
--добавляю условие стоимости эконома > бизнеса
with busines as (
	select tf.flight_id, min(tf.amount) busines_amount
	from ticket_flights tf 
	where tf.fare_conditions = 'Business'
	group by tf.flight_id 
),
economy as (
	select tf.flight_id, max(tf.amount) economy_amount
	from ticket_flights tf 
	where tf.fare_conditions = 'Economy'
	group by tf.flight_id 
)
select a.city departure, a2.city arrival, min(busines.busines_amount) busines_amount, max(economy.economy_amount) economy_amount
from busines 
left join economy on busines.flight_id = economy.flight_id
join flights f on busines.flight_id = f.flight_id 
join airports a on f.departure_airport = a.airport_code 
join airports a2 on f.arrival_airport = a2.airport_code
where economy_amount > busines_amount
group by  a.city, a2.city

--Q Между какими городами нет прямых рейсов?
--A сделал 2 одинаковых vie со списком городов
--затем из декартового произведения убрал строки с одинаковыми городами например Москва Москва
--через оператор except убрал строки с городами из таблицы с перелетами
--distinct для того что бы убрать одинаковые строки, например из Москвы можно вылететь
--из 3-х аэропортов, но город вылета всеравно один

create view city as 
	select a.city 
	from airports a 

create view city2 as 
	select a.city 
	from airports a 

select  c.city "from", c2.city "to"
from city c
cross join city2 c2
where c.city != c2.city
except 
	select distinct a.city dep, a2.city arr
	from flights f 
	join airports a on f.departure_airport = a.airport_code 
	join airports a2 on f.arrival_airport = a2.airport_code

--Q Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с допустимой максимальной дальностью 
-- перелетов  в самолетах, обслуживающих эти рейсы
--A для вычисления расстояния между городами использовал предоставленную формулу, использовал тригонометрические ф-ции
-- так как они помогают избежать ошибок округления. 
select distinct a2.city dep, a3.city arr,  
round((acos(sind(a2.latitude)*sind(a3.latitude) + cosd(a2.latitude)*cosd(a3.latitude)*cosd(a2.longitude - a3.longitude)))::numeric*6371, 2) dist,
ai.model, ai."range", ai."range" - round((acos(sind(a2.latitude)*sind(a3.latitude) + cosd(a2.latitude)*cosd(a3.latitude)*cosd(a2.longitude - a3.longitude)))::numeric*6371, 2) difference
from flights f 
join airports a2 on f.departure_airport = a2.airport_code 
join airports a3 on f.arrival_airport = a3.airport_code 
join aircrafts ai on f.aircraft_code = ai.aircraft_code 

