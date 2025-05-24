create extension if not exists pgcrypto;

--select pg_size_pretty(pg_database_size('inventory2'));


drop table users cascade;
drop table profile_pictures;
drop table buildings cascade;
drop table departments cascade;
drop table integrants;
drop table public.integrants_roles;
drop table requests cascade;
drop table request_details;

create table users(
	id int 	generated always as identity primary key,
	user_name varchar(180) not null,
	last_name varchar(180) not null,
	email varchar(180) unique not null,
	user_password varchar(30) not null,
	created_at timestamp not null,
	is_active boolean not null
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
	is_available boolean not null
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
	completed_on timestamp not null,
	is_satisfied boolean default false not null,
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
drop unlogged table if exists user_tokens;
create unlogged table user_tokens(
	user_id int references users(id) on delete cascade,
	token text,
	primary key (user_id)
);
--inserts
drop function if exists insert_new_user;
create function insert_new_user(user_name varchar(180), last_name varchar(180), email varchar(180), user_password varchar(30))
returns text as $$ 
declare 
	user_token text;
	user_id int;
begin
	insert into users(user_name, last_name, email, user_password, created_at, is_active)
	values (user_name, last_name, email, pgp_sym_encrypt(user_password, 'AES_KEY'),  current_timestamp, false);
	user_token := pgp_sym_encrypt(user_name || last_name || email ||current_timestap);
	user_id := select id from users where email = email;
	insert into user_tokes (user_id, user_token);
	return user_token;
end;
$$ language plpgsql;

select insert_new_user('Miguel', 'Pradera', 'miguelpradera@gmail.com', 'pass123');


--select sum(0.1::numeric) from generate_series(1, 10);
--show timezone;
