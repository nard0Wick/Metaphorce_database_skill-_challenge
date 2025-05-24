

drop table if exists users cascade;
drop table if exists profile_pictures;
drop table if exists buildings cascade;
drop table if exists departments cascade;
drop table if exists integrants_roles cascade;
drop table if exists integrants;
drop table if exists requests cascade;
drop table if exists request_details;

create table users(
	id int 	generated always as identity primary key,
	user_name varchar(180) not null,
	last_name varchar(180) not null,
	email varchar(90) not null,
	user_password varchar(30) not null,
	created_at timestamp not null,
	is_active boolean not null
);

create table profile_pictures(
	id int references users on delete cascade,
	profile_picture text,
	primary key (id)
);

create table buildings(
	id int generated always as identity primary key,
	bulding_reference varchar(180) not null,
	postal_code varchar(30) not null,
	state varchar(90) not null,
	city varchar(90) not null,
	address varchar(180) not null,
	is_available boolean not null
);

create table departments(
	id int generated always as identity primary key,
	building_id int not null,
	department_name varchar(180) not null,
	description varchar(250),
	status boolean not null,
	constraint fk_building foreign key (building_id) references buildings(id) on delete cascade
);

create table integrant_roles(
	id int generated always as identity primary key,
	role varchar(30) not null
);

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


--select sum(0.1::numeric) from generate_series(1, 10);
--show timezone;
