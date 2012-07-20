module(..., package.seeall)

require 'luasql.mysql'

local Model = require 'bamboo.model'

local Mysql = Model:extend {
    __tag = 'Bamboo.Model.Mysql';
    __name = 'Mysql';
    __desc = 'Abstract mysql definition';

    __fields = {
        ['host']            = {};
        ['port']            = {};
        ['database']        = {};
        ['user']            = {};
        ['password']        = {};

        ['conn']            = {};
    };


    init = function(self,t)
        self.id = self:getCounter() + 1;

        self.host = t.host or '127.0.0.1';
        self.port = t.port or 3306;
        self.database = t.database;
        self.user   = t.user;
        self.password = t.password;

        if t.conn ~= nil then
            self:connect();
        end

        return self;
    end;

    connect = function(self,password)
        local mysql_env = luasql.mysql();
        if password == nil then
            self.conn,err = mysql_env:connect( self.database,
                                                    self.user,
                                                    self.password,
                                                    self.host,
                                                    self.port);
        else
            self.conn,err = mysql_env:connect( self.database,
                                                    self.user,
                                                    password,
                                                    self.host,
                                                    self.port);

        end
                                            
        return err or "connected";
    end;

    retrieve = function(self, sqlstr)
        local cur = self.conn:execute(sqlstr);
        
        if type(cur) == 'number' or type(cur)== 'string' then 
            return cur;
        end

        local records = List();
        local numrows = cur:numrows();
        local colnames = cur:getcolnames();
        for i=1,numrows,1 do
            local record = {};
            local temp = {};
            cur:fetch(temp);
            --print("temp");
            for k,v in ipairs(colnames) do
              --  print(k,v);
                record[v] = temp[k];
            end
            
            records:append(record);
        end

        cur:close();

        return records;
    end;

    close = function(self)
        self.conn:close();
    end;


    getFromFile = function(self,datFile,achFile)
        local fields = nil;
        if achFile then 
            local file = io.open(achFile,"r");
            if file then 
                fields = {};
                for line in file:lines() do 
                    table.insert(fields, string.split(line,'\t')[4]);
                end
                io.close(file);
            end
        end

        local records = {};
        if fields then 
            local file = io.open(datFile,"r");
            if file then 
                for line in file:lines() do 
                    local record = {};
                    local temp = string.split(line,'\t');
                    for k,field in ipairs(fields) do 
                        record[field] = temp[k];
                    end

                    table.insert(records, record);
                end

                io.close(file);
            end
        else
            local file = io.open(datFile,"r");
            if file then 
                for line in file:lines() do 
                    local record = string.split(line,'\t');
                    table.insert(records, record);
                end

                io.close(file);
            end
        end

        return records;
    end;

    writeDbToFile = function(self)
        local cur = self.conn:execute("show tables");

        local tables = {};
        local numrows = cur:numrows();
        for i=1,numrows,1 do
            local temp ={};
            cur:fetch(temp);
            tables[i] = temp[1];
        end
        cur:close();

        for i,v in ipairs(tables) do 
            print(v,self.database)
            self.conn:execute("use information_schema");
            self.conn:execute("select * from columns where table_name='"..v.."' and table_schema='" ..self.database.. "' into outfile '/tmp/".. v .. ".ach'");
            self.conn:execute("use "..self.database);
            self.conn:execute("select * from ".. v .. " into outfile '/tmp/".. v .. ".dat'");
        end
    end;

    writeDataToFile = function(self, sqlStr, file)
        local cur = self.conn:execute(sqlStr.." into outfile '"..file.."'");
        return cur;
    end
}

return Mysql;
