require("process")
require("strutil")
require("stream")
require("dataparser")
require("terminal")
require("filesys")
require("time")
require("net")
require("hash")


DISPLAY_CONTROLS=0
DISPLAY_PROJECTS=1
DISPLAY_TASKS=2
DISPLAY_LOGS=3



--[[
Set these to the email, username and password that you use to create accounts on boinc projects
OR use the environment variables BOINC_USERNAME, BOINC_EMAIL and BOINC_PASSWORD which override these
OR use the -user, -email and -pass command-line arguments that override other methods
]]--
acct_username=""
acct_email=""
acct_pass=""
acct_mgr=""

-- gui key can be set here if you only connect to one boinc instance. Otherwise you can set the key with
-- the '-key' command-line argument, and save it with the '-save' option.
gui_key=""

default_port="31416"
server_url=""
boinc_host="tcp:127.0.0.1:"..default_port
boinc_dir=process.homeDir().."/.boinc"
save_key="n"
menu_tabbar=""

hosts={}
boinc_settings={} 

MainMenu=nil

function ToBoolean(val)

if val== nil then return "false" end
if val== "true" then return "true" end
if val== "1" then return "true" end
return "false"
end


function ProjectsSort(p1, p2)
return(p1.name < p2.name)
end


function TasksSort(t1, t2)
return(t1.slot < t2.slot)
end


function SortTable(unsorted_table, sort_func)
local i, item
local sorted={}

for i,item in pairs(unsorted_table) do table.insert(sorted, item) end
table.sort(sorted, sort_func)

return sorted
end


function FormatTime(isecs)
local str, secs, mins, hours

secs=isecs % 60;
isecs=isecs - secs;
mins=(isecs / 60) % 60;
isecs=isecs - (mins * 60);
hours=isecs / 3600;

str=string.format("%02d:%02d:%02d", hours, mins, math.floor(secs))
return str
end



function SaveGuiKey()
local S

if strutil.strlen(server_url) > 0 and strutil.strlen(gui_key) > 0
then
filesys.mkdir(boinc_dir)
S=stream.STREAM(boinc_dir.."/keys.txt","a")
S:writeln(server_url.." "..gui_key.."\n")
S:close()
end

end


function BoincRPCAuth(S)
local P, I, str

if strutil.strlen(gui_key)==0 then return false end

S:writeln("<boinc_gui_rpc_request>\n<auth1/>\n</boinc_gui_rpc_request>\n\003");
str=S:readto("\003")
P=dataparser.PARSER("xml", str);
I=P:open("/boinc_gui_rpc_reply");
str=I:value("nonce") .. gui_key 
str=hash.hashstr(str, "md5", "hex")
S:writeln("<boinc_gui_rpc_request>\n<auth2>\n<nonce_hash>"..str.."</nonce_hash>\n</auth2>\n</boinc_gui_rpc_request>\n\3")

str=S:readto("\003")
P=dataparser.PARSER("xml", str);
if strutil.strlen(P:value("/boinc_gui_rpc_reply/authorized")) > 0 then return true end

return false
end



function BoincRPCResult(P, Type)

if strutil.strlen(P:value("/boinc_gui_rpc_reply/success")) > 0 
then 
Out:bar(" SUCCESS: "..Type.." request processed","fcolor=white bcolor=green")
process.sleep(2)
return true
else
Out:bar(" ERROR: " .. Type .. "request failed. " .. P:value("/boinc_gui_rpc_reply/error"), "fcolor=white bcolor=red");
Out:readln()
end

return false
end


function BoincTransaction(xml, CheckSuccess, Type)
local S, P, str, result

S=stream.STREAM(boinc_host)
Out:bar("Sending "..Type.." request to server ...", "fcolor=yellow bcolor=magenta")
BoincRPCAuth(S)
S:writeln(xml)
str=S:readto("\003")
P=dataparser.PARSER("xml", str)

if CheckSuccess then result=BoincRPCResult(P, Type) end
S:close()

return P
end



-- parser and subitems are global here, to allow us to remember the logs between displays, and not fetch them fresh every time
function GetLogs()
	g_LogParser=BoincTransaction("<boinc_gui_rpc_request>\n<get_messages/>\n</boinc_gui_rpc_request>\n\003",false, "Get Logs")
	g_Logs=g_LogParser:open("/boinc_gui_rpc_reply/msgs")
	return g_Logs
end



function ParseProjectListItem(info)
local proj={}


proj.name=info:value("name")
proj.url=info:value("url")
proj.descript=info:value("summary")
proj.detail=info:value("description")
proj.location=info:value("home")
proj.type=info:value("general_area")
proj.subtype=info:value("specific_area")
proj.logo=info:value("image")

return proj
end


function BoincGetProjectList()
local S, P, plist, item, str
local projects={}

S=stream.STREAM(boinc_dir.."project_list.xml", "r")
if S==nil
then
	filesys.copy("https://boinc.berkeley.edu/project_list.php", boinc_dir.."project_list.xml")
	S=stream.STREAM(boinc_dir.."project_list.xml", "r")
end

str=S:readdoc()
P=dataparser.PARSER("xml", str)
plist=P:open("/projects")
item=plist:first()
while item ~= nil
do
	proj=ParseProjectListItem(item)
	projects[proj.url]=proj
	item=plist:next()
end

S:close()

return projects
end



function BoincParseProjectGuiURL(info)
local gui_url={}

gui_url.name=info:value("name")
gui_url.descript=info:value("description")
gui_url.url=info:value("url")

return gui_url
end



function BoincParseProject(info)
local urls, item
local project={}

project.name=string.gsub(info:value("project_name"), " ", "_")
project.state="active"
project.cpid=info:value("cross_project_id")
project.url=info:value("master_url")
project.user=info:value("user_name")
project.team=info:value("team_name")
project.userid=info:value("userid")
project.teamid=info:value("teamid")
project.hostid=info:value("hostid")
project.credit=tonumber(info:value("user_total_credit"))
project.host_credit=tonumber(info:value("host_total_credit"))
project.jobs_done=tonumber(info:value("njobs_success"))
project.jobs_fail=tonumber(info:value("njobs_error"))
project.jobs_queued=0
project.jobs_active=0
project.disk_usage=0
project.time=tonumber(info:value("elapsed_time"))
if project.time == nil then project.time=0 end

if strutil.strlen(info:value("dont_request_more_work")) > 0 then project.state="nomore" end
if strutil.strlen(info:value("suspended_via_gui")) > 0 then project.state="suspend" end

project.gui_urls={}
urls=info:open("gui_urls")
if urls ~=nil
then
	item=urls:first()
	while item ~= nil
	do
	table.insert(project.gui_urls, BoincParseProjectGuiURL(item))
	item=urls:next()
	end
end


return(project)
end



function BoincParseWorkunit(info)
local wu={}
local val

wu.slot=-1
wu.name=info:value("name")
wu.url=info:value("project_url")
wu.state="queued"
wu.pid=0
wu.progress=0
wu.cpu_time=0

wu.remain_time=tonumber(info:value("estimated_cpu_time_remaining"))
if wu.remain_time == nil then wu.remain_time=0 end

wu.received=tonumber(info:value("received_time"))
wu.deadline=tonumber(info:value("report_deadline"))

if info:value("active_task") ~=nil 
then 
wu.slot=tonumber(info:value("active_task/slot")) 
if wu.slot == nil then wu.slot=-1 end
wu.pid=tonumber(info:value("active_task/pid")) 
if wu.pid == nil then wu.pid=0 end
wu.progress=tonumber(info:value("active_task/fraction_done")) 
if wu.progress == nil then wu.progress=0 end
wu.cpu_time=tonumber(info:value("active_task/current_cpu_time"))
if wu.cpu_time == nil then wu.cpu_time=0 end

val=tonumber(info:value("active_task/active_task_state")) 
if val==1 
then 
wu.state="run" 
else
wu.state="pause"
end

wu.state_val=info:value("active_task/active_task_state")

end

return(wu)
end






function ParseHostInfo(info) 
local host={}

host.name=info:value("domain_name")
host.ip=info:value("ip_addr")
host.cpus=info:value("p_ncpus")
host.processor=info:value("p_model")
host.os=info:value("os_name")
host.os_version=info:value("os_version")
host.fpops=tonumber(info:value("p_fpops"))
host.iops=tonumber(info:value("p_iops"))
host.mem=tonumber(info:value("m_nbytes"))

return host
end




function BoincUpdateProjectTasks(projects, workunits)
local i, wu, proj

for i,wu in pairs(workunits)
do
	proj=projects[wu.url]
	if proj ~= nil
	then
		wu.proj_name=proj.name
		proj.jobs_queued= proj.jobs_queued + 1
		if wu.state == "run"
		then
			proj.jobs_active= proj.jobs_active + 1
		end
	end
end

end






function BoincAcctLookupAuthenticator(S, url, email, passwd)
local str, P

str=passwd..email
str=hash.hashstr(str, "md5", "hex")

S:writeln("<boinc_gui_rpc_request>\n<lookup_account>\n   <url>" ..url .. "</url>\n   <email_addr>".. email .. "</email_addr>\n   <passwd_hash>".. str .."</passwd_hash>\n   <ldap_auth>0</ldap_auth>\n   <server_assigned_cookie>0</server_assigned_cookie>\n   <server_cookie></server_cookie>\n</lookup_account>\n</boinc_gui_rpc_request>\n\003")
str=S:readto("\003")

while true
do
	S:writeln("<boinc_gui_rpc_request>\n<lookup_account_poll/>\n</boinc_gui_rpc_request>\n\003")
	str=S:readto("\003")
	P=dataparser.PARSER("xml", str)
	result=P:value("/boinc_gui_rpc_reply/account_out/error_num")
	if result ~= "-204" then break end
	process.sleep(1)
end

print("errno: "..result)

P=dataparser.PARSER("xml", str)
str=P:value("/boinc_gui_rpc_reply/account_out/authenticator")

return(str)
end



function BoincAttachProject(S, url, authenticator)
return(BoincTransaction("<boinc_gui_rpc_request>\n<project_attach>\n  <project_url>".. url .. "</project_url>\n  <authenticator>" .. authenticator .. "</authenticator>\n  <project_name></project_name>\n</project_attach>\n</boinc_gui_rpc_request>\n\003", true, "Attach Project"))
end



function BoincJoinProject(url, authenticator)
local str, P

Out:bar("Joining "..url, "fcolor=black bcolor=yellow")
str=acct_pass..acct_email
str=hash.hashstr(str, "md5", "hex")

S=stream.STREAM(boinc_host)
BoincRPCAuth(S)

str="<boinc_gui_rpc_request>\n<create_account>\n   <url>".. url .. "</url>\n   <email_addr>" .. acct_email .. "</email_addr>\n   <passwd_hash>" .. str .. "</passwd_hash>\n   <user_name>" .. acct_username .. "</user_name>\n   <team_name></team_name>\n</create_account>\n</boinc_gui_rpc_request>\n\3"

S:writeln(str)

str=S:readto("\003")
P=dataparser.PARSER("xml", str)

while true
do
	S:writeln("<boinc_gui_rpc_request>\n<create_account_poll/>\n</boinc_gui_rpc_request>\n\003")
	str=S:readto("\003")

	P=dataparser.PARSER("xml", str)
	print("errno: ".. P:value("/boinc_gui_rpc_reply/account_out/error_num"))
	if P:value("/boinc_gui_rpc_reply/account_out/error_num") ~= "-204" then break end
	process.sleep(1)
end

str=P:value("/boinc_gui_rpc_reply/account_out/authenticator")
if strutil.strlen(str) ==0
then
	print(P:value("/boinc_gui_rpc_reply/account_out/error_num"))
	print(P:value("/boinc_gui_rpc_reply/account_out/error_msg"))

	--try looking up authenticator
	str=BoincAcctLookupAuthenticator(S, url, acct_email, acct_pass)
end

BoincAttachProject(S, url, str)

S:close()

end




function BoincRunBenchmarks()
return(BoincTransaction("<boinc_gui_rpc_request>\n<run_benchmarks/>\n</boinc_gui_rpc_request>\n\003", true, "Run Benchmarks"))
end



function BoincShutdown()
return(BoincTransaction("<boinc_gui_rpc_request>\n<quit/>\n</boinc_gui_rpc_request>\n\003",true, "SHUTDOWN"))
end


function BoincNetworkAvailable()
return(BoincTransaction("<boinc_gui_rpc_request>\n<network_available/>\n</boinc_gui_rpc_request>\n\003",true, "Network available"))
end



function BoincAcctMgrSync()
return(BoincTransaction("<boinc_gui_rpc_request>\n<acct_mgr_rpc>\n  <use_config_file/>\n</acct_mgr_rpc>\n</boinc_gui_rpc_request>\n\003",true, "Sync with account manager"))
end

function BoincAcctMgrLeave()
--send all empty arguments to leave any currently configured account manager
P=BoincTransaction("<boinc_gui_rpc_request>\n<acct_mgr_rpc>\n<url></url>\n<name></name>\n<password></password>\n</acct_mgr_rpc>\n</boinc_gui_rpc_request>\n\003", true, "Leave account manager")
end


function BoincAcctMgrSet(url)
local S, P, str, result

BoincAcctMgrLeave()
P=BoincTransaction("<boinc_gui_rpc_request>\n<acct_mgr_rpc>\n<url>"..url.."</url>\n<name>"..acct_username.."</name>\n<password>"..acct_pass.."</password>\n</acct_mgr_rpc>\n</boinc_gui_rpc_request>\n\003", false, "Join account manager")

result=BoincRPCResult(P, "Join account manager")
if result
then
S=stream.STREAM(boinc_host)
BoincRPCAuth(S)
while true
do
	S:writeln("<boinc_gui_rpc_request>\n<acct_mgr_rpc_poll/>\n</boinc_gui_rpc_request>\n\003")
	str=S:readto("\003")
	P=dataparser.PARSER("xml", str)
	result=P:value("/boinc_gui_rpc_reply/acct_mgr_rpc_reply/error_num")
	if result ~= "-204" then break end
	process.sleep(1)
end

print("result: [".. result.."]")
S:close()
end

end



function BoincAcctMgrLookup()
local P
local mgr={}

P=BoincTransaction("<boinc_gui_rpc_request>\n<acct_mgr_info/>\n</boinc_gui_rpc_request>\n\003", false, "Lookup account manager info")

if strutil.strlen(P:value("/boinc_gui_rpc_reply/acct_mgr_info/acct_mgr_url")) > 0
then
mgr.name=P:value("/boinc_gui_rpc_reply/acct_mgr_info/acct_mgr_name")
mgr.url=P:value("/boinc_gui_rpc_reply/acct_mgr_info/acct_mgr_url")
return(mgr)
end

return(nil)
end


function BoincUpdateProjectsDiskUsage(state, projects)
local items, item, url, du

P=BoincTransaction("<boinc_gui_rpc_request>\n<get_disk_usage/>\n</boinc_gui_rpc_request>\n\003",false,"Get Disk Usage")
items=P:open("/boinc_gui_rpc_reply/disk_usage_summary")
state.disk_usage=tonumber(items:value("d_boinc"))
state.disk_total=tonumber(items:value("d_total"))
state.disk_free=tonumber(items:value("d_free"))

item=items:next()
while item ~= nil
do
	if item:name()=="project"
	then
		url=item:value("master_url")
		if url ~= nil
		then
		du=tonumber(item:value("disk_usage"))
		state.disk_usage=state.disk_usage + du
		projects[url].disk_usage=du
		end
	end
	item=items:next()
end

return(nil)
end




function BoincGetState()
local str, host, proj, task, S
local state={}

state.projects={}
state.tasks={}

S=stream.STREAM(boinc_host)
if S==nil then return nil end


Out:puts("\n~yPLEASE WAIT - UPDATING DATA FROM BOINC~0\n")
if BoincRPCAuth(S) ~= true then return "unauthorized" end



S:writeln("<boinc_gui_rpc_request>\n<get_state/>\n</boinc_gui_rpc_request>\n\003")
str=S:readto("\003")
S:close()

P=dataparser.PARSER("xml", str)

I=P:open("/boinc_gui_rpc_reply/client_state")
item=I:first()
while item ~= nil
do
if item:name()=="host_info" 
then 
	state.host=ParseHostInfo(item) 
	state.host.client_version=I:value("core_client_major_version") .. "." .. I:value("core_client_minor_version") .. "." .. I:value("core_client_release")
end

if item:name()=="project" 
then 
	proj=BoincParseProject(item)
	state.projects[proj.url]=proj
end

if item:name()=="result" 
then 
	task=BoincParseWorkunit(item)
	state.tasks[task.name]=task
end


item=I:next()
end


BoincUpdateProjectsDiskUsage(state, state.projects)
BoincUpdateProjectTasks(state.projects, state.tasks);
state.acct_mgr=BoincAcctMgrLookup()

return state
end


function BoincSettingGetDescription(name)
if boinc_settings[name]==nil then return "" end
if boinc_settings[name].description==nil then return "" end
return boinc_settings[name].description
end

function BoincSettingIsBoolean(name)
if boinc_settings[name]==nil then return false end
if boinc_settings[name].dtype=="bool" then return true end
return false
end

function BoincSettingIsNumeric(name)
if boinc_settings[name]==nil then return false end
if boinc_settings[name].dtype=="num" then return true end
return false
end

function BoincSettingIsInteger(name)
if boinc_settings[name]==nil then return false end
if boinc_settings[name].dtype=="int" then return true end
return false
end

function BoincSettingIsIgnored(name)
if boinc_settings[name]==nil then return false end
if boinc_settings[name].dtype=="ignore" then return true end
return false
end



function BoincXMLAddValue(XML, id, name, value)
XML=XML.."<"..name..">"
if BoincSettingIsBoolean(id) == true
then
	if ToBoolean(value) == "true"
	then
		XML=XML.."1"
	else
		XML=XML.."0"
	end
else
	XML=XML..value
end

XML=XML.."</"..name..">\n"

return XML
end

function BoincSetClientConfig(Config)
local str, id, name, value

str="<boinc_gui_rpc_request>\n<set_cc_config>\n"
for id,value in pairs(Config)
do
	if string.sub(id, 1, 3)=="cc:"
	then
	name=string.sub(id, 4)						
	str=BoincXMLAddValue(str, id, name, value)
	end
end
str=str.. "</set_cc_config>\n</boinc_gui_rpc_request>\n\003"

BoincTransaction(str, true, "Set client config (cc_config.xml)")
P=BoincTransaction("<boinc_gui_rpc_request>\n<read_cc_config/>\n</boinc_gui_rpc_request>\n\003", false, "Read cc_config file")
end


function BoincSetGlobalPrefs(Config)
local str, id, name, value

str="<boinc_gui_rpc_request>\n<set_global_prefs_override>\n<global_preferences>\n"
for id,value in pairs(Config)
do
	if string.sub(id, 1, 6)=="prefs:"
	then
	name=string.sub(id, 7)						
	str=BoincXMLAddValue(str, id, name, value)
	end
end
str=str.. "</global_preferences>\n</set_global_prefs_override>\n</boinc_gui_rpc_request>\n\003"

BoincTransaction(str, true, "Set Global Preferences")
BoincTransaction("<boinc_gui_rpc_request>\n<read_global_prefs_override/>\n</boinc_gui_rpc_request>\n\003", true, "Activate Preferences")
end



function BoincParseSetting(Config, prefix, name, value)
local id

id=prefix..name;
if BoincSettingIsBoolean(id) 
then 
	Config[id]=ToBoolean(value)
elseif BoincSettingIsInteger(id)
then
	Config[id]=string.format("%d", tonumber(value))
elseif BoincSettingIsNumeric(id)
then
	Config[id]=string.format("%0.3f", tonumber(value))
else 
	Config[id]=value
end
end



function BoincUpdateClientConfig(Config)
local P, items, name, value

P=BoincTransaction("<boinc_gui_rpc_request>\n<get_cc_config/>\n</boinc_gui_rpc_request>\n\003",false, "Get Client Config")
items=P:open("/boinc_gui_rpc_reply")
if items ~= nil
then
	item=items:first()
	while item ~= nil
	do
		BoincParseSetting(Config, "cc:", item:name(), item:value())
		item=items:next()
	end
end


P=BoincTransaction("<boinc_gui_rpc_request>\n<get_global_prefs_working/>\n</boinc_gui_rpc_request>\n\003",false, "Get Global Preferences")
items=P:open("/boinc_gui_rpc_reply/global_preferences")
if items ~= nil
then
item=items:first()
while item ~= nil
do
	BoincParseSetting(Config, "prefs:", item:name(), item:value())
	item=items:next()
end
end

end






function BoincSettingDisplayModifyScreen(Config, name)
local value

Out:clear()
Out:move(0,1)
Out:puts("Modify value: ~e~b"..name.."~0\n")
Out:puts("Description: ~e~b".. BoincSettingGetDescription(name) .."~0\n\n")
Out:puts("Current Value: "..Config[name].."\n")
value=Out:prompt("Enter new Value: ")

Config[name]=value
end


function BoincSettingGetName(setting)
local tokens

tokens=strutil.TOKENIZER(setting, ":")

--throw away first token
tokens:next()
return( string.gsub(tokens:next(), "_", " "))
end


function BoincConfigScreenRefresh()
Out:clear()
Out:move(0,0)
Out:puts("Configure boinc@"..boinc_host.."~0\n")
Out:puts(" Some settings may require restarting boinc to take effect\n")
Out:puts(" ~R~wDon't forget to select SAVE CONFIG at the bottom of the menu~0\n")
Out:bar("esc:back  up/down:select item   enter:modify", "fcolor=blue bcolor=cyan")
end


function BoincSettingModify(Config, name)

if BoincSettingIsBoolean(name)==true
then
	if ToBoolean(Config[name])=="true"
	then
		Config[name]="false"
	else
		Config[name]="true"
	end
else
	BoincSettingDisplayModifyScreen(Config, name)
	BoincConfigScreenRefresh()
end

end



function DisplayBoincConfigRunMenu(Menu)
local Selected=nil
local ch, curr, str

while Selected == nil
do
	ch=Out:getc()
	if ch=="ESC" then break end
	Selected=Menu:onkey(ch)

	-- check this feature exists before trying to use it, earlier versions of
	-- libUseful-lua don't have this
	if Menu.curr ~= nil
	then
		curr=Menu:curr()
		if curr ~= nil 
		then
			Out:move(1, Out:length()-3)
			Out:puts(BoincSettingGetDescription(curr).."~>")
		end
	end
	Out:flush()
end

return Selected
end


function DisplayBoincConfigScreen()
local Menu, P, name, value, pos
local Config={} 
local Sorted={}
local Selected=""

for name, value in pairs(boinc_settings)
do
Config[name]="false"
end

BoincUpdateClientConfig(Config)
for name, value in pairs(Config)
do
	table.insert(Sorted, name)
end

table.sort(Sorted)

BoincConfigScreenRefresh()
while Selected ~= nil
do
Menu=terminal.TERMMENU(Out, 1, 4, Out:width() -2, Out:length()-9)
for pos, name in pairs(Sorted)
do
	if BoincSettingIsIgnored(name) == false
	then
	value=Config[name]
	if value=="true" then value="~w~etrue~0" end
	if value=="false" then value="~bfalse~0" end
	Menu:add(string.format("% 30s:  %s", BoincSettingGetName(name), value), name)
	end
end

Menu:add("~rSAVE CONFIG - push changes to boinc~0", "save")

Menu:draw()
Selected=DisplayBoincConfigRunMenu(Menu)

if Selected ~= nil
then
if Selected=="save"
then
	BoincSetClientConfig(Config)
	BoincSetGlobalPrefs(Config)
	break
else 
	BoincSettingModify(Config, Selected)
end
end
end

end





function BoincProjectOperation(Selected, proj)
local op, str, S

if strutil.strlen(Selected) == 0 then Selected="exit" end
if Selected=="exit" then return end

if Selected=="update" then op="project_update" end
if Selected=="pause" then op="project_suspend" end
if Selected=="resume" then op="project_resume" end
if Selected=="reset" then op="project_reset" end
if Selected=="finish" then op="project_nomorework" end
if Selected=="more" then op="project_allowmorework" end
if Selected=="detach" then op="project_detach" end
if Selected=="final" then op="project_detach_when_done" end

if op ~= nil
then
S=stream.STREAM(boinc_host)
str="<boinc_gui_rpc_request>\n<" .. op .. ">\n  <project_url>" ..  proj.url .. "</project_url>\n</"..op..">\n</boinc_gui_rpc_request>\n\003"
if BoincTransaction(str, true, Selected .. " project")
then
	if Selected=="pause" then proj.state="suspend" end
	if Selected=="resume" then proj.state="active" end
	if Selected=="finish" then proj.state="nomore" end
	if Selected=="more" then proj.state="active" end
end
S:close()
end

end



function DisplayProjectDetails(proj)
local i, gurl

Out:clear()
Out:move(0,0)
Out:puts("~e".. proj.name .. "~0  ~y" .. proj.url .. "~0" .. "    cpid: ".. proj.cpid .. "\n")

if proj.state=="active" 
then 
	if proj.jobs_active > 0 
	then
	Out:puts(string.format("state: ~gRUNNING~0  (%d active jobs)\n", proj.jobs_active))
	elseif proj.jobs_queued > 0 
	then
		Out:puts("state: ~yactive - work queued~0\n")
	else
		Out:puts("state: ~cactive - no work~0\n")
	end
elseif proj.state=="nomore" 
then
	if proj.jobs_active > 0 
	then
		Out:puts("state: ~mfinish current but don't get more~0\n")
	else 
		Out:puts("state: ~rdon't get work~0\n")
	end
elseif proj.state=="suspend" 
then
	Out:puts("state: ~rpaused~0\n")

end

Out:puts("~euser:~0 ".. proj.userid .. "  ".. proj.user .. "   ~eteam:~0 ".. proj.teamid .. "  ".. proj.team .."\n")
Out:puts("~ehost:~0 ".. proj.hostid .. "  ~etime consumed:~0 ".. FormatTime(proj.time) .."\n")
if proj.time > 0 
then 
	Out:puts(string.format("credit:  host: %0.3f    user:%0.3f    host/h:%0.3f   host/m:%0.3f\n", proj.host_credit, proj.credit, proj.host_credit * 3600 / proj.time, proj.host_credit * 60 / proj.time))
else
	Out:puts(string.format("credit:  host: %0.3f    user:%0.3f    host/h:%0.3f   host/m:%0.3f\n", proj.host_credit, proj.credit, proj.host_credit * 3600 / proj.time, proj.host_credit * 60 / proj.time))
end

Out:puts(string.format("jobs:  done: %d  queued:%d  active:%d  failed:%d \n", proj.jobs_done, proj.jobs_queued, proj.jobs_active, proj.jobs_fail))

Out:puts("\n");

for i,gurl in pairs(proj.gui_urls)
do
Out:puts(gurl.name ..": " .. gurl.url .."\n")
end

end



function DisplayProject(proj)
local Menu, Selected
local ProjectsAltered=false

DisplayProjectDetails(proj)
Out:bar("q:exit app  left/right:select menu  up/down/enter:select item  u:update", "fcolor=blue bcolor=cyan")

Menu=terminal.TERMMENU(Out, 1, 15, Out:width() -2, Out:length()-17)
Menu:add("update  - connect to project server", "update")
if proj.state=="suspend" 
then
Menu:add("resume  - resume working on project", "resume")
else
Menu:add("pause   - suspend working on project", "pause")
end

if proj.state=="nomore" 
then
Menu:add("more    - resume getting work", "more")
else
Menu:add("finish  - finish curr work, but dont get more", "finish")
end

Menu:add("reset   - delete curr work and get more", "reset")
Menu:add("detach  - delete curr work and quit project", "detach")
Menu:add("final   - complete current work then quit project", "final")
Menu:add("exit    - exit menu", "exit")

while Selected ~= "exit"
do
	Selected=Menu:run()
	if Selected == nil then Selected="exit" end
	if Selected ~= "exit" 
	then 
		ProjectsAltered=true 
		break
	end
	BoincProjectOperation(Selected, proj)
	DisplayProjectDetails(proj)
end

return ProjectsAltered
end






function BoincTaskOperation(Selected, task)
local op, str

if Selected == nil then Selected="exit" end

if Selected ~= "exit" 
then
	Out:puts("\n"..Selected.. " task "..task.name.."\n")
	if Selected=="abort" then op="abort_result" end
	if Selected=="pause" then op="suspend_result" end
	if Selected=="resume" then op="resume_result" end

	str="<boinc_gui_rpc_request>\n<" .. op .. ">\n  <project_url>" ..  task.url .. "</project_url>\n<name>" .. task.name .. "</name></"..op..">\n</boinc_gui_rpc_request>\n\003"

	if BoincTransaction(str, true, op)
	then
			if op=="abort_result" then Selected="exit"
			elseif op=="suspend_result" then task.state="pause"
			elseif op=="resume_result" then task.state="run"
			end
	end
end

return Selected 
end



function DisplayTask(task)
local Menu, i
local Selected=""


while true
do
	Out:clear()
	Out:move(0,0)
	Out:puts("\n~e".. task.proj_name .. "~0  ~y" .. task.url .. "~0" .. "\n")
	Out:puts("Task:".. task.name.."\n")
	
	if task.state=="run" then str="~gactive~0"
	elseif task.state=="pause" then str="~rPAUSED~0"
	else str="queued"
	end
	
	Out:puts("State:".. str.."  ".. task.state_val.."\n")
	Out:puts("Slot:".. task.slot .. "  Pid:" .. task.pid .. "\n")
	Out:puts(string.format("Progress: %0.2f%%   Time: %s  Remain: %s\n", task.progress * 100, FormatTime(task.cpu_time), FormatTime(task.remain_time)))
	Out:puts("Received: " .. time.formatsecs("%Y/%m/%d %H:%M:%S", task.received) .. "  Deadline: " .. time.formatsecs("%Y/%m/%d %H:%M:%S", task.deadline) .. "\n")

	Out:bar("q:exit app  left/right:select menu  up/down/enter:select item  u:update", "fcolor=blue bcolor=cyan")
	
	Menu=terminal.TERMMENU(Out, 1, 8, Out:width() - 2, 10)
	if task.state=="run"
	then
	Menu:add("pause   - suspend task", "pause")
	else
	Menu:add("resume  - resume task", "resume")
	end
	
	Menu:add("abort   - abandon task", "abort")
	Menu:add("exit    - exit menu", "exit")
	
	Selected=Menu:run()
	if Selected == nil then Selected="exit" end
	if Selected=="exit" then break end
	Selected=BoincTaskOperation(Selected, task)
end

end










function DisplayProjectsMenu()
local projects, sorted, url, proj, Selected
local wid, len

Out:clear()
Out:bar("up/down/enter:select menu item   esc:back", "fcolor=white bcolor=blue")
Out:move(0,0)
Out:puts("~B~wSELECT PROJECT~>~0\n")
projects=BoincGetProjectList()
sorted=SortTable(projects, ProjectsSort)
wid=Out:width() - 2
len=Out:length() -3
Menu=terminal.TERMMENU(Out, 0, 0, wid, len)

for url,proj in pairs(sorted)
do
	str=proj.name .. "  " .. proj.url .. "  " .. proj.descript;

	if strutil.strlen(str) > wid-2 then str=string.sub(str, 1, wid-2) end
	Menu:add(str, proj.url)
end

Selected=Menu:run()

Out:clear()
Out:move(0,0)
return Selected
end






function StartBoincLocalhost()
local pid

	filesys.mkdir(boinc_dir)
	Out:puts("~yStarting boinc~0\n")
	pid=process.xfork()
	if pid==0
	then
		process.chdir(boinc_dir)
		os.execute("boinc --daemon")
		--we will only get here if os.execute fails
		os.exit(0)
	else
		process.wait(pid)
		--allow time for boinc to start up

		for i=1,5,1
		do
		process.sleep(1)
		S=stream.STREAM(boinc_host)
		if S ~= nil
		then
			S:close()
			break
		end

		end
		S=stream.STREAM(boinc_dir.."/gui_rpc_auth.cfg")
		if S ~=nil
		then
		gui_key=S:readln()
		S:close()
		SaveGuiKey()
		end
			
	end
end



function StartBoincSSHhost()
local pid

	filesys.mkdir(boinc_dir)
	Out:puts("~yStarting boinc~0\n")
	pid=process.xfork()
	if pid==0
	then
		process.chdir(boinc_dir)
		Out:close()
		os.execute("boinc --daemon")
		process.sleep(2)
		os.exit(0)
	else
		process.wait(pid)
		S=stream.STREAM(boinc_dir.."/gui_rpc_auth.cfg")
		gui_key=S:readln()
		S:close()

		SaveGuiKey()
	end
end



function AskToConnectToHost(server_url)
local str

if server_url ~= "tcp://localhost"
then
return false
end

Out:puts("\n~rbonic is not running on target host. Start it? [Y/n]~0\n")
str=Out:getc()
if str=="Y" or str=="y"
then
	StartBoincLocalhost()
	return true
end

return false
end



function ProcessControl(Selected)

if Selected=="shutdown"
then
	if BoincShutdown() then return "exit" end
elseif Selected=="update_acct_mgr"
then
	BoincAcctMgrSync()
elseif Selected=="benchmark"
then
	BoincRunBenchmarks()
elseif Selected=="network_available"
then
	BoincNetworkAvailable()
elseif Selected=="configure"
then
	DisplayBoincConfigScreen()
end

return ""
end



function JoinProjectScreen()
	if strutil.strlen(acct_email)==0 or strutil.strlen(acct_username)==0 or strutil.strlen(acct_pass)==0
	then
		Out:clear()
		Out:move(0,4)
		Out:puts("~R~wERROR: cannot join projects without email, username and password.\n")
		Out:puts("~R~wPlease restart and provide this information on the command line. \n")
		Out:puts("~R~w               PRESS ANY KEY                                     \n")
		Out:getc()
	else
		Selected=DisplayProjectsMenu()
		if strutil.strlen(Selected) > 0 then BoincJoinProject(Selected) end
	end
end





function DisplayHostBanner(state)
Out:move(0, 0)
Out:puts("~mHost:~0 ~e".. state.host.name .. "~0 ~c(" .. state.host.ip .. ")~0   ".. state.host.os .. " - " .. state.host.os_version.. "\n")
Out:puts("~mCPU:~0 " .. state.host.cpus .. "*" .. state.host.processor .. "\n")
Out:puts("~mOPS/s:~0  ~cinteger:~0 " .. strutil.toMetric(state.host.iops, 2) .. "   ~cfloating-point:~0 " .. strutil.toMetric(state.host.fpops, 2) .. "\n")
Out:puts("~mMEM:~0 " .. strutil.toMetric(state.host.mem)  .. "\n")
Out:puts("~mDISK:~0  ~ctotal:~0 " .. strutil.toMetric(state.disk_total) .. "  ~cfree:~0" .. strutil.toMetric(state.disk_free) .. "  ~cboinc usage:~0 "..strutil.toMetric(state.disk_usage) .. "\n")
Out:puts("~mBoinc Version:~0 ".. state.host.client_version .."\n")
if state.acct_mgr ~= nil and strutil.strlen(state.acct_mgr.name) > 0 
then 
	Out:puts("~mAccount Manager:~0 ".. state.acct_mgr.name .. "  " .. state.acct_mgr.url .."\n") 
else
	Out:puts("~mAccount Manager:~0 ~r~enone~0" .."\n") 
end

end


-- refresh the screen. Doesn't change any details of what's displayed (that's done in MenuSwitch and it's subfunctions)
-- but pushes all the data out to the display
function ScreenRefresh(Menu, display_state, boinc_state)

Out:cork()
Out:clear()
DisplayHostBanner(boinc_state)
Out:move(1,8)
Out:puts(menu_tabbar)
Menu:draw()

Out:bar("q:exit app  left/right:select menu  up/down/enter:select item  u:update", "fcolor=blue bcolor=cyan")
Out:flush()
end


-- load main control options menu
function ControlMenu(Menu)
local Selected

	menu_tabbar=" [~eControl~0]  Projects   Tasks    Log    "
	Menu:add("configure", "configure")
	Menu:add("contact servers (tell boinc network is available)", "network_available")
	Menu:add("update account manager", "update_acct_mgr")
	Menu:add("run benchmarks", "benchmark")
	Menu:add("shutdown boinc", "shutdown")
	Menu:add("exit app", "exit")
end



-- load up log messages from boinc, ready to be displayed
function LogMenu(Menu)
local P, item, str, when

	--tasks=SortTable(unsort_tasks, TasksSort)
	menu_tabbar="  Control   Projects   Tasks   [~eLog~0]   "

	if g_Logs==nil then g_Logs=GetLogs() end

	item=g_Logs:first()
	while item ~= nil
	do
		str=strutil.stripTrailingWhitespace(item:value("body"))
		str=strutil.stripLeadingWhitespace(str)
		when=time.formatsecs("%Y/%m/%d %H:%M:%S  ", tonumber(item:value("time"))) 
		str=string.format("%s %20s   %s", when, item:value("project"), str)
		Menu:add(string.sub(str, 1, Out:width() -8))
	item=g_Logs:next()
	end

	Menu:add("exit app", "exit")

	return true
end


-- load up details of running tasks ready to be displayed
function TasksMenu(Menu, unsort_tasks)
local Selected, i, task, due
local tasks={}

	tasks=SortTable(unsort_tasks, TasksSort)
	menu_tabbar="  Control   Projects  [~eTasks~0]   Log    "
	menu_tabbar=menu_tabbar..string.format("\n   %4s % 20s %6s  %7s  %8s  %8s %8s\n", "slot", "project",  "state", "percent", "cpu time", "remaining", "due")
	for i,task in pairs(tasks)
	do
		if task.slot > -1
		then
			due=time.formatsecs("%y/%m/%d", task.deadline)
			Menu:add(string.format("%04d % 20s %6s % 7.2f%%  %8s   %8s %8s", task.slot, string.sub(task.proj_name,1,25), task.state, task.progress * 100.0, FormatTime(task.cpu_time), FormatTime(task.remain_time), due),  task.name)
		end
	end
	Menu:add("exit app", "exit")

	return true
end



-- load up details of attatched projects ready to be displayed
function AttachedProjectsMenu(Menu, unsort_projects)
local Selected, i, proj
local projects={}
local str, name

	projects=SortTable(unsort_projects, ProjectsSort)

	menu_tabbar="  Control  [~eProjects~0]  Tasks    Log   "
	
	str=string.format("\n   %20s % 7s % 5s % 6s % 6s % 6s", "name", "credit",  "queue", "active", "done", "fail")
	if Out:width() > 82
	then
		str=str..string.format(" %7s  % 10s  % 10s", "disk use", "cred/hour", "cred/min")
	end
	menu_tabbar=menu_tabbar..str

	Menu:add("[add new project]", "new_project")
	for i,proj in pairs(projects)
	do
		if proj.jobs_active ==0 and (proj.state=="nomore" or proj.state=="suspend")
		then 
			active="PAUSED"
		else
			active=string.format("%6d", proj.jobs_active)
		end

		if strutil.strlen(proj.name)==0
		then
		name="** ADDING **   " .. proj.url
		else
		name=string.sub(proj.name, 1, 20)

		str=string.format("%20s % 7s % 5d %s % 6d % 6d", name, strutil.toMetric(proj.host_credit),  proj.jobs_queued, active, proj.jobs_done, proj.jobs_fail)

		if Out:width() > 82 
		then
				str=str..string.format("   %6s", strutil.toMetric(proj.disk_usage))
				if proj.time > 0
				then
				str=str..string.format("  % 8.2f  % 8.2f", proj.host_credit * 3600 / proj.time, proj.host_credit * 60 / proj.time)
				end
		end
		end
		
		Menu:add(str, proj.url)
	end
	Menu:add("exit app", "exit")
end


-- when we switch between menus we need to rebuild them (i.e. load their details into the Menu object)
function MenuSwitch(display_state, boinc_state)

Menu=terminal.TERMMENU(Out, 1, 10, Out:width() - 2, Out:length() -14)
Menu:clear()
io.stderr:write("ms: "..tostring(display_state).."\n")
if display_state==DISPLAY_LOGS
then
	LogMenu(Menu)
elseif display_state==DISPLAY_TASKS
then
	TasksMenu(Menu, boinc_state.tasks)
elseif display_state==DISPLAY_PROJECTS
then
	AttachedProjectsMenu(Menu, boinc_state.projects)
else
	ControlMenu(Menu)
end

return Menu
end


-- Read input from the user to select items from the menus, 
-- or switch between the menus
function DisplayHostProcessMenu(display_state, boinc_state)
local ch, Selected

while true
do
	-- if we get a SIGWINCH signal, it means the screen has changed size, and we have to rebuild the menu
	-- to fit the new width/height of the screen
	if process.sigcheck(process.SIGWINCH)==true then MainMenu=MenuSwitch(display_state, boinc_state) end

	-- refresh the screen, doesn't change any details, just pushes the current screen to the terminal
	ScreenRefresh(MainMenu, display_state, boinc_state)

	--watch for a SIGWINCH (window size changed) signal
	process.sigwatch(process.SIGWINCH)

	-- read a character from the user and act on it
	ch=Out:getc()
	if ch=="q" 
	then 
		return "exit", display_state 
	elseif ch == "u"
	then
		boinc_state=BoincGetState()
		if display_state==DISPLAY_LOGS then GetLogs() end
	elseif ch=="LEFT" 
	then 
		display_state=display_state - 1
		if display_state < 0 then display_state=0 end
		MainMenu=MenuSwitch(display_state, boinc_state)
	elseif ch=="RIGHT" 
	then 
		display_state=display_state + 1
		if display_state > DISPLAY_LOGS then display_state=DISPLAY_LOGS end
		MainMenu=MenuSwitch(display_state, boinc_state)
	elseif ch ~= ""
	then
		Selected=MainMenu:onkey(ch)
		if Selected ~= nil then return Selected, display_state end
	end
	
end

end



-- this is the main interactive screen, it displays info on the boinc processes
-- running on a given host
function DisplayHost(server_url)
local host, projects, tasks, ch, mgr
local display_state=0
local boinc_state, result


if string.sub(server_url, 1, 4)=="ssh:" 
then 
	host=string.sub(server_url, 5) 
	net.setProxy("sshtunnel:"..host)
else
	boinc_host=server_url..":"..default_port
end

Out:clear()
Out:move(0,0)
Out:puts("~yConnecting to host [~0~e"..server_url.."~y]~0\n")

boinc_state=BoincGetState()
if boinc_state==nil
then
	Out:puts("~rERROR: failed to connect to boinc at " .. server_url.."~0\n")
	if AskToConnectToHost(server_url) 
	then 
		boinc_state=BoincGetState() 
	else
		return
	end
elseif boinc_state=="unauthorized" 
then
	Out:puts("~rERROR: authorization failed~0\n")
	if strutil.strlen(gui_key) ==0 then Out:puts("~rno authorization key supplied. Please supply it with the -key command-line option~0\n") end
	return
end


if boinc_state ~= nil
then

if strutil.strlen(acct_mgr) > 0 
then
	if acct_mgr == "none" 
	then
	BoincAcctMgrLeave()
	else
	BoincAcctMgrSet(acct_mgr)
	end
end

--sets us to the default menu
MainMenu=MenuSwitch(display_state, boinc_state)
while true
do
	Selected,display_state=DisplayHostProcessMenu(display_state, boinc_state)

	if Selected=="exit" 
	then 
		break
	elseif Selected=="new_project"
	then
		JoinProjectScreen()
	else
		if display_state==DISPLAY_PROJECTS
		then
			DisplayProject(boinc_state.projects[Selected])
		elseif display_state==DISPLAY_TASKS
		then
			DisplayTask(boinc_state.tasks[Selected])
		else
			result=ProcessControl(Selected)
			if result=="exit" then break end
		end
	end
end

Out:clear()
Out:move(0,0)
else

Out:puts("~rERROR: failed to connect to host~0\n");
end


end


-- if more than one host has been registered that we can connect to and control
-- then this function is called and displays the 'select host' menu
function QueryUserForHost()
local Menu, name, key

	Out:clear()

	Out:move(0,3)
	Out:puts("~B~wSelect host to connect to... ~>~0\n")
	Menu=terminal.TERMMENU(Out, 1, 4, Out:width() - 2, Out:length()-5)
	for name,key in pairs(hosts)
	do
		if name ~= "size" then Menu:add(name) end
	end
	Menu:add("exit") 

	selected=Menu:run()
	if selected=="exit" then return nil end
	return selected
end



function PrintHelp()

	print("usage: bonic_mgr.lua [url] [options]");
	print("");
	print("options:")
	print("   -key <gui key>      key from gui_rpc_auth.cfg file for boinc server")
	print("   -user <username>    boinc username needed for joining projects")
	print("   -email <email>      boinc email needed for joining projects")
	print("   -pass  <pass>       boinc password needed for joining projects")
	print("   -save               save gui_key for url")
	print("   -?                  this help")
	print("   -h                  this help")
	print("   -help               this help")
	print("   --help              this help")
	print("")
	print("If no arguments are supplied, boinc_mgr.lua will try to connect to a boinc server at the localhost. If none is running it will ask if one should be started. For such a locally started server boinc_mgr.lua can look up the key from the server's key file. For one it hasn't started itself, or one that is running on a remote host, it needs to be told the key using the -key argument.\n")
 	print("boinc_mgr supports two types of url. 'tcp' and 'ssh' urls. 'ssh' urls refer to named configurations in the ssh configuration file normally stored in ~/.ssh/config, and must be configured to auto-login using a private key. boinc_mgr will use these to log into a remote host, then connect to a boinc server running locally on 127.0.0.1. 'tcp' urls just connect directly to a boinc server.\n")
	print("You can store urls and keys using the '-save' argument like this:")
	print("   boinc_mgr.lua <url> -key <key> -save")
	print("If you save a number of such urls and keys then the program will start to offer a choice of hosts to connect to\n")
  print("If you are going to attach projects to a boinc server, then you'll need to supply the -user, -email and -pass arguments for that project. These are never stored on disk.")
	
	os.exit()
end


function ParseCmdLine(arg)
local host="localhost"
local i


i=1
while i <= #arg
do
	if strutil.strlen(arg[i]) > 0
	then
		if arg[i] == "-key" 
		then 
			i=i+1
			gui_key=arg[i]
		elseif arg[i] == "-user"
		then
			i=i+1
			acct_username=arg[i]
		elseif arg[i] == "-email"
		then
			i=i+1
			acct_email=arg[i]
		elseif arg[i] == "-pass"
		then
			i=i+1
			acct_pass=arg[i]
		elseif arg[i] == "-acct_mgr"
		then
			i=i+1
			acct_mgr=arg[i]
		elseif arg[i] == "-save"
		then
			save_key="y"
		elseif arg[i] == "-?" or arg[i] == "-h" or arg[i] == "-help" or arg[i] == "--help"
		then
			PrintHelp()
		else
			server_url=arg[i]
		end
	end
	i=i+1
end



end




function BoincLoadHosts()
local S, str, host, key

S=stream.STREAM(boinc_dir.."/keys.txt","r")
if S ~= nil
then
str=S:readln()
while str ~= nil
do

	str=strutil.stripTrailingWhitespace(str)
	toks=strutil.TOKENIZER(str, " ")
	host=toks:next()
	key=toks:next()

	hosts[host]=key
	str=S:readln()
end
S:close()
end

end


function BoincMgrAddSetting(name, dtype, description)
local setting={}

setting.name=name
setting.dtype=dtype
setting.description=description
boinc_settings[setting.name]=setting
end


function BoincMgrInit()
local tempstr

tempstr=process.getenv("BOINC_USERNAME")
if strutil.strlen(tempstr) > 0 then acct_username=tempstr end
tempstr=process.getenv("BOINC_EMAIL")
if strutil.strlen(tempstr) > 0 then acct_email=tempstr end
tempstr=process.getenv("BOINC_PASSWORD")
if strutil.strlen(tempstr) > 0 then acct_pass=tempstr end

BoincMgrAddSetting("cc:abort_jobs_on_exit", "bool", "If boinc shuts down then throw away current tasks")
BoincMgrAddSetting("cc:allow_multiple_clients", "bool", "Allow multiple boinc clients on one machine")
BoincMgrAddSetting("cc:allow_remote_gui_rpc", "bool", "Allow RPC from hosts other than localhost")
BoincMgrAddSetting("cc:fetch_minimal_work", "bool", "Get one job per device")
BoincMgrAddSetting("cc:fetch_on_update", "bool", "Fetch work when updating")
BoincMgrAddSetting("cc:report_results_immediately", "bool", "Send results as soon as computed")
BoincMgrAddSetting("cc:suppress_net_info", "bool", "Don't send ip details to servers")
BoincMgrAddSetting("prefs:run_on_batteries", "bool", "Option for laptops: run boinc tasks even when on batteries")
BoincMgrAddSetting("prefs:run_if_user_active", "bool", "Run boinc tasks even if computer is being used")
BoincMgrAddSetting("prefs:run_gpu_if_user_active", "bool", "Use GPU (if supported) even when computer is being used")
BoincMgrAddSetting("prefs:suspend_if_no_recent_input", "bool", "Suspend work if no recent user mouse/keyboard activity. Allows system to go into powersave.")
BoincMgrAddSetting("prefs:leave_apps_in_memory", "bool", "Don't swap apps out of memory when prempted by kernel.")
--BoincMgrAddSetting("cc:skip_cpu_benchmarks", "bool", "")
BoincMgrAddSetting("cc:skip_cpu_benchmarks", "ignore", "")
--BoincMgrAddSetting("cc:exit_when_idle", "bool", "")
BoincMgrAddSetting("cc:exit_when_idle", "ignore", "")
--BoincMgrAddSetting("prefs:dont_verify_images", "bool", "")
BoincMgrAddSetting("prefs:dont_verify_images", "ignore", "")
--BoincMgrAddSetting("prefs:confirm_before_connecting", "bool", "")
BoincMgrAddSetting("prefs:confirm_before_connecting", "ignore", "")
BoincMgrAddSetting("prefs:hangup_if_dialed", "bool", "")
BoincMgrAddSetting("prefs:network_wifi_only", "bool", "")
BoincMgrAddSetting("prefs:disk_min_free_gb", "num", "Leave at least this much disk free")
BoincMgrAddSetting("prefs:disk_max_used_gb", "num", "Max diskspace to use in Gigabytes")
BoincMgrAddSetting("prefs:disk_max_used_pct", "num", "Max percent of diskspace to use")
BoincMgrAddSetting("prefs:vm_max_used_pct", "num", "Max percent of virtual memory (including swap) to use")
BoincMgrAddSetting("prefs:idle_time_to_run", "num", "Wait for system idle this many minutes before running boinc tasks")
BoincMgrAddSetting("prefs:max_ncpus_pct", "num", "Percent of cpus to use")
BoincMgrAddSetting("prefs:daily_xfer_limit_mb", "num", "Max per-day data transfer in megabytes")
BoincMgrAddSetting("prefs:ram_max_used_busy_pct", "num", "Percent of ram to use when system is in use")
BoincMgrAddSetting("prefs:ram_max_used_idle_pct", "num", "Percent of ram to use when system is idle")
BoincMgrAddSetting("prefs:battery_charge_min_pct", "num", "Stop tasks if laptop battery percent charge is lower than this")
BoincMgrAddSetting("prefs:battery_max_temperature", "num", "Stop tasks if laptop battery gets hotter than this")
BoincMgrAddSetting("prefs:cpu_usage_limit", "num", "Max percent cpu to use")
BoincMgrAddSetting("prefs:suspend_cpu_usage", "num", "Suspend tasks if non boinc processes use over this much cpu")
BoincMgrAddSetting("prefs:cpu_scheduling_period_minutes", "num", "Minutes to run a project for before switching to another")
BoincMgrAddSetting("prefs:disk_interval", "num", "Seconds between writing task state to disk. Minimum is 60 seconds. No maximum.")
BoincMgrAddSetting("prefs:max_bytes_sec_up", "num", "Upload speed for workunit/application transfers")
BoincMgrAddSetting("prefs:max_bytes_sec_down", "num", "Download speed for workunit/application transfers")
BoincMgrAddSetting("prefs:work_buf_min_days", "num", "Download work to last at least this many days")
BoincMgrAddSetting("prefs:work_buf_additional_days", "num", "Download additional work for this many days")
BoincMgrAddSetting("prefs:start_hour", "int", "Run tasks only after this hour to 'end hour'")
BoincMgrAddSetting("prefs:end_hour", "int", "Run tasks only before this hour from 'start hour'")
BoincMgrAddSetting("prefs:net_start_hour", "int", "Do upload/download only after this hour to 'net end hour'")
BoincMgrAddSetting("prefs:net_end_hour", "int", "Do upload/download only before this hour from 'net start hour'")


BoincMgrAddSetting("prefs:override_file_present", "ignore", "")
BoincMgrAddSetting("prefs:mod_time", "ignore", "")
BoincMgrAddSetting("prefs:source_project", "ignore", "")
end



function SelectHost(server_url)
local key, str
local size=0

if strutil.strlen(server_url) > 0 then return net.reformatURL(server_url) end

-- only way to get an accurate table size!
for key,str in pairs(hosts)
do
	size=size+1
end


if size > 1
then
	server_url=QueryUserForHost()
else
	server_url="tcp://localhost"
end

return server_url
end


-- MAIN STARTS HERE --

--process.lu_set("HTTP:Debug","y");
BoincMgrInit()

ParseCmdLine(arg)

Out=terminal.TERM()
--Out:hidecursor()

BoincLoadHosts()
server_url=SelectHost(server_url)

if strutil.strlen(gui_key) ==0 
then 
	gui_key=hosts[server_url] 
elseif save_key == "y" 
then 
	SaveGuiKey() 
end 
DisplayHost(server_url) 

Out:reset()

