Bamboo Commands
===============

### `bamboo createapp app_name`

Create your project's directory hierarchy.

### `bamboo start`

At the root of your project directory, entering `bamboo start` will run your project. 

### `bamboo test`

At the root of your project directory, entering `bamboo test` will run all  unit tests in the `tests/` of this project. 

### `bamboo help`

Print this command list.

### `bamboo stop`

At the root of your project directory, entering `bamboo stop` will stop the running project process. 

### `bamboo createplugin plugin_name`

At the `plugins/` directory, entering `bamboo createplugin plugin_name` will create a new plugin directory with `plugin_name` as its name.

### `bamboo createmodel model_name`

At the `models/` directory, entering `bamboo createmodel model_name` will create a new model file with `model_name` as its name.

### `bamboo initdb luadb_file`

Use this command to initial db with the data of `luadb_file`.

### `bamboo pushdb luadb_file`

Use this command to push data to db with the data of `luadb_file`.

### `bamboo clearmodel model_name`

Use this command to clear all data about model `model_name`. 

### `bamboo shell`

Use this command to enter the lua shell specified with this project, in this shell you can debug code and db.

### `bamboo loadconfig`

Used to generate config.sqlite file for mongrel2. This command must be used at the root of the `monserver_dir`.

### `bamboo startserver server_name`

Used to start mongrel2's server. This command must be used at the root of the `monserver_dir`.

### `bamboo stopserver server_name`

Used to stop mongrel2's server. This command must be used at the root of the `monserver_dir`.

### `bamboo createsuperuser`

Create a super user in db for this project.
