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
        
        if type(cur) == 'number' then 
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

}

return Mysql;
