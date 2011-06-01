CREATE FUNCTION active_services(date) RETURNS setof varchar AS $$
select service_id from (
  select service_id from calendar 
  where service_days[(select to_char($1, 'ID'))::int] = true and start_date <= $1 and end_date >= $1
  UNION
  select service_id from calendar_dates 
  where exception_type = 'add' and date = $1
) services
EXCEPT 
  select service_id from calendar_dates 
  where exception_type = 'remove' and date = $1;
$$ language sql;

CREATE FUNCTION active_trips(date) RETURNS SETOF trips AS $$
select * from trips where service_id in (select active_services($1) as service_id);
$$ LANGUAGE SQL;

CREATE FUNCTION adjusted_time(x timestamp with time zone) RETURNS character(8) AS $$
DECLARE
  h integer;
  m integer;
  s  integer;
BEGIN
  h := extract(hour from x);
  m := extract(minutes from x);
  IF h  < 4 THEN 
    h := h + 24;
  END IF;
  RETURN lpad(h::text, 2, '0') || ':' || m || ':00';
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION adjusted_date(x timestamp with time zone) RETURNS date AS $$
BEGIN
  IF extract(hour from x) < 4 THEN 
    RETURN date( x - interval '24 hours' );    
  ELSE 
    RETURN date(x);
  END IF;
END;
$$ LANGUAGE plpgsql;


CREATE FUNCTION available_routes(timestamp with time zone) RETURNS setof record AS $$
select a.route_type, a.route, a.direction_id, 
coalesce(b.trips_left, 0), b.headsign from 
(select r.route_type, coalesce(nullif(r.route_long_name, ''), nullif(r.route_short_name, '')) route, trips.direction_id
from active_trips(adjusted_date($1)) as trips inner join routes r using (route_id)
group by r.route_type, route, trips.direction_id) a
left outer join
  (select r.route_type, coalesce(nullif(r.route_long_name, ''), nullif(r.route_short_name, '')) route, 
  trips.direction_id,
  count(*) as trips_left,
  max(trip_headsign) as headsign
  from active_trips(adjusted_date($1)) as trips inner join routes r using (route_id) 
  where trips.finished_at > adjusted_time($1)
  group by r.route_type, route, trips.direction_id) b
  on (a.route_type = b.route_type and a.route = b.route and a.direction_id = b.direction_id)
  order by route_type, route, direction_id;
$$ language sql;



CREATE FUNCTION route_trips_today(varchar, int) RETURNS SETOF trips AS $$
select trips.* 
from active_trips(date(now())) as trips 
inner join routes r using (route_id) 
where trips.direction_id = $2 and coalesce(nullif(r.route_long_name, ''), nullif(r.route_short_name, '')) = $1;
$$ LANGUAGE SQL;

CREATE FUNCTION stop_times_today(varchar, int) RETURNS SETOF stop_times AS $$
select * from stop_times st where trip_id in 
(select trip_id from route_trips_today($1, $2))
order by stop_id, arrival_time, stop_sequence;
$$ LANGUAGE SQL;

