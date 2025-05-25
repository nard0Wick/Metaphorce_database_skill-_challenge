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
	/*token := generate_token(user_name, last_name, email);
	select u.id into user_id from users u where u.email = email;
	insert into user_tokens(user_id, token, created_at) values(user_id, token, current_timestamp);*/
end;
$$ language plpgsql;

--user insertions
--in order to be able of validating a token, you must execute one insertion at a time, then take the token and validate it
select insert_user('Miguel', 'Juárez', 'migueljuarez@gmail.com', 'MysuperPassword');
select validate_token('\xc30d040703029707eb412efb9f0a74d2570141d3fb90c531a919a620d84e89cd787f461f943a53b06bd9355e439c60225b98d6816ddeabfa63b25a05b17ba3626ca888150d029b1e6b18d3c9743e8c799b538f18e5eb9a236be9230f1ee8930d512f99f6891394ce');
--checking for account_validation on user and user_tokens tables
select u.user_name, u.last_name, u.email, u.is_active, u_t.created_at, u_t.checked_at, u_t.is_checked 
from users u, user_tokens u_t
where u.id = u_t.user_id;
--whether validation process last more than three minutes, a new token will be required
select insert_user('Pedro', 'Prieto', 'pedroprieto@gmail.com', 'noPassword');
--requesting a new token
select generate_token('Pedro', 'Prieto', 'pedroprieto@gmail.com');
select validate_token('\xc30d04070302d6891cbc67570f607ed254019adc39b909a14e25ac004d02d5acb503424d459aa47834c38e2a71731f22c457688c43c6f6dae5bb6b4b6e00643c467f3a7f7c73e0df52ecd716f70166eb21c2cace3b98166095eab0308fc74152ccae1868e4');
--if the token expires account activation won't be successful
select u.user_name, u.last_name, u.email, u.is_active, u_t.created_at, u_t.checked_at, u_t.is_checked 
from users u, user_tokens u_t
where u.id = u_t.user_id;

/*select * from users;

select  insert_user('Uzzy', 'Zaz', 'uz@gmail.com', 'pass123');
select generate_token('Uzzy', 'Zaz', 'uz@gmail.com');
select validate_token('\xc30d04070302e35bb9d8dfbc5cc77bd24701cde4bb1a682d8d0d020813e0cb5f355e039e2701b3b826b611532a8bfd16d993799fd6f345db4a96fd0a4049c2044b3943e5fea6ca74f780fb4d66a523821599dde4595b5a46');

select * from users;
select * from user_tokens;

select insert_user('Miguel', 'Quezada', 'miguelquezada@gmail.com', 'pass123');
select generate_token('Miguel', 'Quezada', 'miguelquezada@gmail.com');

select generate_token('pedro', 'perez', 'pp@gmail.com');
select validate_token('\xc30d04070302d896d6ee4afa50737ed26401f3c6a791d28cfc12b09d7c1b8e452cc441622b454d2b7c5666e21a5c1b3f86dca2385d4b56441054e3cbd9f5a43d0e4b6995a022baf1decf1a347fd27424c7e44d3b7cda1e71713b89042dad28aaceaef5535f9a923d7f92e3c7392c229575887ff405');

select substring('pedroperezpp@gmail.com 2025-05-23 23:05:10.399322-06', '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');

select insert_new_user('Miguel', 'Pradera', 'miguelpradera@gmail.com', 'pass123');

select current_timestamp + make_interval(mins => 5);*/


--select sum(0.1::numeric) from generate_series(1, 10);
--show timezone;
