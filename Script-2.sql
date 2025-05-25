create extension if not exists pgcrypto;

--select pg_size_pretty(pg_database_size('inventory2'));


drop table users cascade;
drop table profile_pictures;
drop table buildings cascade;
drop table departments cascade;
drop table integrants;
drop table requests cascade;
drop table request_details;
--drop table integrants_roles; --only manually

create table users(
	id int 	generated always as identity primary key,
	user_name varchar(180) not null,
	last_name varchar(180) not null,
	email varchar(180) unique not null,
	user_password text not null,
	created_at timestamp not null,
	is_active boolean default false
);
drop index if exists idx_email;
create index if not exists idx_email on users using hash (email);

create table profile_pictures(
	id int references users on delete cascade,
	profile_picture text,
	primary key (id)
);

create table buildings(
	id int generated always as identity primary key,
	building_reference varchar(180) not null,
	postal_code varchar(30) not null,
	state varchar(90) not null,
	city varchar(90) not null,
	address varchar(180) not null,
	is_available boolean default true not null
);

drop index if exists idx_building_reference;
--b-tree
create index if not exists idx_building_reference on buildings(building_reference);

create table departments(
	id int generated always as identity primary key,
	building_id int not null,
	department_name varchar(180) not null,
	description varchar(250),
	status boolean not null,
	constraint fk_building foreign key (building_id) references buildings(id) on delete cascade
);

drop index if exists idx_department_name_description;
create index if not exists idx_department_name_description on departments using gin (to_tsvector('spanish', department_name || ' ' || description));

create table integrant_roles(
	id int generated always as identity primary key,
	role varchar(30) not null
);

--drop index if exists idx_integrant_role;
--create index if not exists idx_integrant_role on integrant_roles using hash (role);

create table integrants(
	id int generated always as identity primary key,
	user_id int not null,
	department_id int not null,
	building_id int not null,
	integrant_role_id int not null,
	constraint fk_user foreign key (user_id) references users(id) on delete cascade,
	constraint fk_department foreign key (department_id) references departments(id) on delete cascade,
	constraint fk_building foreign key (building_id) references buildings(id) on delete cascade,
	constraint fk_integrant_role foreign key (integrant_role_id) references integrant_roles(id) on delete restrict
);

create table requests(
	id int generated always as identity primary key,
	user_id int not null,
	ordered_date timestamp not null,
	completed_on timestamp,
	is_satisfied boolean default false,
	constraint fk_user foreign key (user_id) references users(id) on delete cascade
);

create table request_details(
	id int generated always as identity primary key,
	request_id int not null,
	product_reference varchar(180) not null,
	quantity int not null,
	constraint fk_request foreign key (request_id) references requests(id) on delete cascade
);

--creating unlogged table for storing tokens
drop table if exists user_tokens;
create unlogged table user_tokens(
	user_id int references users(id) on delete cascade,
	token text,
	created_at timestamp,
	checked_at timestamp default null,
	is_checked boolean default false,
	primary key (user_id)
);

--functions emulating tokenization process 
drop function if exists generate_token;
create function generate_token(user_name varchar(180), last_name varchar(180), user_email varchar(180))
returns text as $$
declare
	_token text;
	u_id int;
	is_present boolean;
begin
	_token := pgp_sym_encrypt(' ' || user_name || ' ' || last_name || ' ' || user_email, 'AES_KEY');
	select id into u_id from users  where email = user_email;
	select exists (select user_id from user_tokens where user_id = u_id)::boolean into is_present ;
	if is_present then
		update user_tokens
		set token = _token, created_at = current_timestamp
		where user_id = u_id;
	else
		insert into user_tokens(user_id, token, created_at) values(u_id, _token, current_timestamp);
	end if;
	return _token;
end;
$$ language plpgsql;

drop function if exists validate_token;
create function validate_token(user_token text)
returns void as $$
declare
	old_ timestamp;
	decripted_data text;
	u_email varchar(180);
	u_id int;
begin 
	decripted_data := pgp_sym_decrypt(user_token::bytea, 'AES_KEY');
	u_email := substring(decripted_data, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')::varchar(180);
	select id into u_id from users where email = u_email;
	if u_id is not null then
		select created_at into old_ from user_tokens where user_id = u_id;
		if extract (epoch from (current_timestamp - old_)) / 60 < 3 then
			update user_tokens
			set checked_at = current_timestamp, is_checked = true
			where user_id = u_id;
			update users
			set is_active = true
			where id = u_id;
			--return 'true';
		end if;
		--return 'almost :(';
	end if;
	--return 'false'||' '||u_email|| ' ' || user_id;
end;
$$ language plpgsql;

drop function if exists insert_user;
create function insert_user(user_name varchar(180), last_name varchar(180), email varchar(180), user_password varchar(30))
returns text as $$
declare
	token text;
	user_id int;
	encripted_password text;
begin
	encripted_password := pgp_sym_encrypt(user_password, 'AES_KEY');
	insert into users (user_name, last_name, email, user_password, created_at) values(user_name, last_name, email, encripted_password, current_timestamp);
	return generate_token(user_name, last_name, email);
end;
$$ language plpgsql;

--user insertions
--in order to be able of validating a token, you must execute one insertion at a time, then take the token and validate it
select insert_user('Miguel', 'Juárez', 'migueljuarez@gmail.com', 'MysuperPassword');
select validate_token('\xc30d040703023ab80b1b5d1fd1727bd2570152d5e10e4b4f7a25cef0bf1c78ae09d41e9f06bff0dd8751010c5824be11de532fc5d84a0b4f36e163c96087265ad92db78370f519d19bb7322dfb11d80aeda3a353d89782ba9f051af8990d6095435991a3e3f66796');
--checking for account_validation on user and user_tokens tables
select u.user_name, u.last_name, u.email, u.is_active, u_t.created_at, u_t.checked_at, u_t.is_checked 
from users u, user_tokens u_t
where u.id = u_t.user_id;
--whether validation process last more than three minutes, a new token will be required
select insert_user('Pedro', 'Prieto', 'pedroprieto@gmail.com', 'noPassword');
--requesting a new token
select generate_token('Pedro', 'Prieto', 'pedroprieto@gmail.com');
select validate_token('\xc30d04070302b0d997f72bb839207fd2540193e5a23161fb4bcfa1ce23c2ee70dae0125f225ed66b9fe0a0158fbf6aec96e0368f3e0c03b300cc970ead4e88884e352d9e7fef55767be9885c94e2d667415b6df2f6c1e93c1ec7749fbeb86119986f97b3bc');
--if the token expires account activation won't be successful
select u.user_name, u.last_name, u.email, u.is_active, u_t.created_at, u_t.checked_at, u_t.is_checked 
from users u, user_tokens u_t
where u.id = u_t.user_id;

--building insertions
insert into buildings (building_reference, postal_code, state, city, address, is_available)
values ('Institución', '37000', 'Guanajuato', 'León', 'smt', true), ('Institución 2', '37000', 'Guanajuato', 'León', 'smt', true);
--looking at buildings
select * from buildings limit 2;

--department insertions 
insert into departments (building_id, department_name, description, status)
values (1, 'Interrelaciones', 'smt', true), (1, 'Marketing', 'smt', true), (2, 'Soporte técnico', 'smt', true);
--looking at buildings and departments
select b.building_reference, b.postal_code, d.department_name, d.description 
from buildings b, departments d 
where b.id = d.building_id;

--integrant_roles insertions
insert into integrant_roles(role) 
values('Jefe'), ('Asistente');

--integrants insertions
insert into integrants (user_id, department_id, building_id, integrant_role_id)
values(1, 3, 1, 2), (2, 3, 1, 1);

--request insertions
insert into requests (user_id, ordered_date)
values(1, current_timestamp);

--request details insertions
insert into request_details(request_id, product_reference, quantity)
values (1, 'a', 3), (1, 'b', 1), (1, 'c', 2);

--view for requests 
drop view if exists requests_from_users;
create view requests_from_users as
select u.user_name, u.last_name, d.department_name, b.building_reference, b.postal_code, r.ordered_date, r.is_satisfied, r_d.product_reference, r_d.quantity
from users u, departments d, buildings b, requests r, request_details r_d, integrants i
where u.id = r.user_id and r_d.request_id = r.id and u.id = i.user_id and i.building_id = b.id and i.department_id = d.id;

select * from requests_from_users;

--updating requests
update requests 
set completed_on = current_timestamp, is_satisfied = true 
where id = 1;

--removing completed requests
delete from requests 
where is_satisfied = true and extract (epoch from (current_timestamp - completed_on)) / 86400 ::int < 21;
--86400 21

select * from requests;


