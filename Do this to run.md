Do this to setup everything to run as configured:

Open PgAdmin > Select server 'PostGreSQL 17' > In Databases, create new DB called: PostOffice_DB

- in 'PostOffice\PostOffice\PostOffice_Proj\PostOffice_Proj\settings.py' : "PASSWORD": "postgres",
    Set your own server 'PostGreSQL 17' password

cd PostOffice\PostOffice_Proj > run the commands:

    pip install django psycopg2-binary pymongo

    py manage.py makemigrations

    py manage.py migrate

Run DML script(PostOffice\populate_data.sql) inside PgAdmin query tool to load data directly to the app

Then try running it
    py manage.py runserver

The users that were defined in the DB DML are in the README.md

