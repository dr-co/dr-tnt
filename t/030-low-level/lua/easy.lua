print(os.getenv('PRIMARY_PORT'))

local box = require 'box';
box.cfg{ listen  = os.getenv('PRIMARY_PORT') }

box.schema.user.create('testrwe', { password = 'test' });
box.schema.user.grant('testrwe', 'read,write,execute', 'universe');
