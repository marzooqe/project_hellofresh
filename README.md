### Hellofresh DBT project
This repository holds the provided raw data files as seed. Base model is stored in "transform" folder and all analytics queries used in the presentation is available as sql files in "analyses" folder. Thses code can be used in DB handler like DBeaver after running dbt compile which puts the code in target/analyses folder.

### Using the project

Run the following commands in terminal (after installing docker if not present):
- in terminal set the current directory to the project folder and execute following commands
- docker-compose up -d
- Once the docker is up and running move to the dbt folder(cd hf_pg_dbt) for data manipulation and follow the below statments
- docker-compose exec dbt bash
- dbt build
- dbt run
- dbt test
- dbt compile

Once the data is available the DB can be accessed with below credentaials
      dbname: hellofresh
      host: postgres
      pass: hf_dbt_password
      port: 5432
      type: postgres
      user: hf_dbt_user 

And execute codes in target folder.