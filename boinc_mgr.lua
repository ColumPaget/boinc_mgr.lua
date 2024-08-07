require("process")
require("strutil")
require("stream")
require("dataparser")
require("terminal")
require("filesys")
require("time")
require("hash")
require("net")
require("sys")


DISPLAY_CONTROLS=0
DISPLAY_PROJECTS=1
DISPLAY_TASKS=2
DISPLAY_LOGS=3

-- position of menus on screen so they don't overwrite status headers
MENU_TOP=10


--[[
Set these to the email, username and password that you use to create accounts on boinc projects
OR use the environment variables BOINC_USERNAME, BOINC_EMAIL and BOINC_PASSWORD which override these
OR use the -user, -email and -pass command-line arguments that override other methods
]]--

acct={}
acct.username=""
acct.email=""
acct.pass=""

config={}
config.acct_mgr=""
-- gui key can be set here if you only connect to one boinc instance. Otherwise you can set the key with
-- the '-key' command-line argument, and save it with the '-save' option.
config.gui_key=""
config.default_port="31416"
config.boinc_dir=process.homeDir().."/.boinc"
config.debug=false;


server_url=""
boinc_host="tcp:127.0.0.1:"..config.default_port
save_key="n"
menu_tabbar=""

hosts={}
boinc_settings={} 
boinc_state=nil

MainMenu=nil


function LookupProject(NameOrURL)
local proj,url


if boinc_state == nil then return(nil) end
proj=boinc_state.projects[NameOrURL]
if proj then return(proj) end

for url,proj in pairs(boinc_state.projects)
do
if proj.name == NameOrURL then return(proj) end
end

return(nil)
end


function LookupProjectName(NameOrURL)
local proj

proj=LookupProject(NameOrURL)
if proj ~= nil then return(proj.name) end
return(NameOrURL)
end





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

if strutil.strlen(server_url) > 0 and strutil.strlen(config.gui_key) > 0
then
filesys.mkdir(config.boinc_dir)
S=stream.STREAM(config.boinc_dir.."/keys.txt","a")
if S ~= nil
then
S:writeln(server_url.." "..config.gui_key.."\n")
S:close()
end
end

end


function BoincError(xml, trans_type)
local errno, errstr, P

P=dataparser.PARSER("xml", xml)
if P ~= nil
then
errno=P:value("/boinc_gui_rpc_reply/"..trans_type.."/error_num");
errstr=P:value("/boinc_gui_rpc_reply/"..trans_type.."/error_string");
if strutil.strlen(errstr)==0
then
  if errno=="-1" then errstr="generic error"
  elseif errno=="-112" then errstr="invalid XML"
  elseif errno=="-136" then errstr="item not found in DB"
  elseif errno=="-137" then errstr="name/email already in use"
  elseif errno=="-138" then errstr="cant open DB"
  elseif errno=="-161" then errstr="item not found"
  elseif errno=="-182" then errstr="file transfer timeout"
  elseif errno=="-183" then errstr="project down"
  elseif errno=="-184" then errstr="http/https comms error"
  elseif errno=="-186" then errstr="work unit download failed"
  elseif errno=="-187" then errstr="work unit upload failed"
  elseif errno=="-189" then errstr="invalid url"
  elseif errno=="-205" then errstr="email bad syntax"
  elseif errno=="-206" then errstr="wrong password"
  elseif errno=="-207" then errstr="email already in use"
  elseif errno=="-208" then errstr="account creation disabled"
  elseif errno=="-209" then errstr="attach failed"
end
end
else
errno=0
errstr="error parsing xml reply"
end

return errno, errstr
end



function BoincConnect(url)
local proxy, dest

if string.sub(url, 1, 4)=="ssh:" 
then 
	proxy=string.sub(url, 5) 
	net.setProxy("sshtunnel:"..proxy)
else
	dest=url..":"..config.default_port
end

if config.debug == true then io.stderr:write("CONNECT: " ..dest.."\n") end
return(stream.STREAM(dest))
end


function BoincRPCAuth(S)
local P, I, str

if strutil.strlen(config.gui_key)==0 then return false end

S:writeln("<boinc_gui_rpc_request>\n<auth1/>\n</boinc_gui_rpc_request>\n\003");
str=S:readto("\003")
P=dataparser.PARSER("xml", str);
I=P:open("/boinc_gui_rpc_reply");
str=I:value("nonce") .. config.gui_key 
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
Out:flush()
process.sleep(2)
return true
else
Out:bar(" ERROR: " .. Type .. " request failed. " .. P:value("/boinc_gui_rpc_reply/error"), "fcolor=white bcolor=red");
Out:flush()
Out:getc()
end

return false
end


function BoincTransaction(xml, CheckSuccess, Type)
local S, P, str, result

S=BoincConnect(server_url)
if S ~= nil
then
if config.debug == true then io.stderr:write("SEND: " ..xml.."\n") end
Out:bar("Sending "..Type.." request to server ...", "fcolor=yellow bcolor=magenta")
BoincRPCAuth(S)
S:writeln(xml)
str=S:readto("\003")
if config.debug == true then io.stderr:write("RECV: " ..str.."\n") end
P=dataparser.PARSER("xml", str)

if CheckSuccess then result=BoincRPCResult(P, Type) end
S:close()
end

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
local P

proj.name=info:value("name")
proj.url=info:value("url")
proj.descript=info:value("summary")
proj.detail=info:value("description")
proj.location=info:value("home")
proj.type=info:value("general_area")
proj.subtype=info:value("specific_area")
proj.logo=info:value("image")

proj.platforms={}
P=info:open("platforms")
if P ~= nil
then
	plat=P:next()
	while plat ~= nil
	do
	table.insert(proj.platforms, plat:value("name"))
	plat=P:next()
	end
end

return proj
end


function BoincGetProjectList()
local S, P, plist, item, str
local projects={}

S=stream.STREAM(config.boinc_dir.."/project_list.xml", "r")
if S==nil
then
	filesys.copy("https://boinc.berkeley.edu/project_list.php", config.boinc_dir.."/project_list.xml")
	S=stream.STREAM(config.boinc_dir.."/project_list.xml", "r")
end

str=S:readdoc()
P=dataparser.PARSER("xml", str)
plist=P:open("/projects")
item=plist:first()
while item ~= nil
do
	if item:name()=="project"
	then
	proj=ParseProjectListItem(item)
	projects[proj.url]=proj
	end

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
local errno, errstr, str, S, P, project_auth

Out:move(0,0)
Out:puts("~B~wJoin project " .. url .." ~>~0\n")
Out:bar("Joining "..url, "fcolor=black bcolor=yellow")
Out:move(0,2)
Out:flush()
str=acct.pass..acct.email
str=hash.hashstr(str, "md5", "hex")

S=BoincConnect(server_url)
if S ~= nil
then
Out:puts("Connected, sending join request\n")
Out:flush()
BoincRPCAuth(S)

str="<boinc_gui_rpc_request>\n<create_account>\n   <url>".. url .. "</url>\n   <email_addr>" .. acct.email .. "</email_addr>\n   <passwd_hash>" .. str .. "</passwd_hash>\n   <user_name>" .. acct.username .. "</user_name>\n   <team_name></team_name>\n</create_account>\n</boinc_gui_rpc_request>\n\3"

S:writeln(str)
if config.debug == true then io.stderr:write("SEND: " ..str.."\n") end

str=S:readto("\003")
if config.debug == true then io.stderr:write("RECV: " ..str.."\n") end

while true
do
	S:writeln("<boinc_gui_rpc_request>\n<create_account_poll/>\n</boinc_gui_rpc_request>\n\003")
	str=S:readto("\003")
	if config.debug == true then io.stderr:write("RECV: " ..str.."\n") end

	errno,errstr=BoincError(str, "account_out")

	if errno ~= "-204" then break end
	process.sleep(1)
end


Out:puts("Got reply: "..errno.." - "..errstr.."\n")
P=dataparser.PARSER("xml", str)
project_auth=P:value("/boinc_gui_rpc_reply/account_out/authenticator")
Out:puts("project authenticator: " .. project_auth .. "\n")
Out:flush()
if strutil.strlen(project_auth) == 0
then
	errno, errstr=BoincError(str, "account_out")
	Out:puts("~rERROR: No project authenticator ErrorCode=" .. errno .. " Error=" .. errstr .."~0\n")
	--try looking up authenticator
	Out:puts("Attempt authenticator lookup... \n")
	Out:flush()
	project_auth=BoincAcctLookupAuthenticator(S, url, acct.email, acct.pass)
	Out:puts("GOT: " .. project_auth .. "\n")
	Out:flush()
end

if strutil.strlen(project_auth) > 0
then 
Out:puts("~gGot project autenticator, attaching to project~0\n")
Out:flush()
BoincAttachProject(S, url, project_auth) 
end

S:close()
end

Out:flush()
process.sleep(2)
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


function BoincAcctMgrSet(url, name, password)
local S, P, str, result, acct_mgr

acct_mgr=BoincAcctMgrLookup()
-- if we are already set to the right account manager then do nothing
if acct_mgr ~= nil and acct_mgr.url ~= nil
then
if url == acct_mgr.url then return end
BoincAcctMgrLeave()
end

if url ~= "none"
then
P=BoincTransaction("<boinc_gui_rpc_request>\n<acct_mgr_rpc>\n<url>"..url.."</url>\n<name>"..name.."</name>\n<password>"..password.."</password>\n</acct_mgr_rpc>\n</boinc_gui_rpc_request>\n\003", false, "Join account manager")

result=BoincRPCResult(P, "Join account manager")
if result
then
S=BoincConnect(server_url)
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

acct_mgr=BoincAcctMgrLookup()
end
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


function BoincAcctMgrConfigScreen()
local user, url, pass

Out:clear()
Out:bar("enter account manager details", "fcolor=blue bcolor=cyan")
Out:move(0,0)
Out:puts("~B~wSETUP ACCOUNT MANAGER~>~0\n")

Out:puts("\n\nEnter url or name for account manager\n")
Out:puts("recognized names:\n")
Out:puts("  bam             -   Boinc Account Manager (default for most people) \n")
Out:puts("  sciu            -   https://scienceuntied.org\n")
Out:puts("  science_united  -   https://scienceuntied.org\n")
Out:puts("  gridrep         -   Grid Republic (www.gridrepublic.org)\n")
Out:puts("  gridrepublic    -   Grid Republic (www.gridrepublic.org)\n")
Out:puts("  grcpool         -   GRCPool, earn grc coins (https://www.grcpool.com)\n")
url=Out:prompt("\nAccount Manager: ")

if strutil.strlen(url) > 0
then

if url=="bam" then url="https://bam.boincstats.com/"
elseif url=="sciu" then url="https://scienceunited.org"
elseif url=="science_united" then url="https://scienceunited.org"
elseif url=="gridrep" then url="https://www.gridrepublic.org"
elseif url=="gridrepublic" then url="https://www.gridrepublic.org"
elseif url=="grcpool" then url="https://www.grcpool.com/"
end

Out:puts("\nAccount Manager URL: "..url.."\n")

Out:puts("\nEnter username on account manager\n")
user=Out:prompt("Username: ")
Out:puts("\nEnter password for account manager\n")
pass=Out:prompt("Password: ")

if strutil.strlen(user) > 0 and strutil.strlen(pass) > 0
then
Out:puts("\n~gAttatching to: "..url .."~0\n")
Out:flush()
BoincAcctMgrSet(url, user, pass)
else
Out:puts("\n~rERROR: unusuable details. press any key~0\n")
Out:flush()
Out:getc()
end

end

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
		if projects[url] ~= nil then projects[url].disk_usage=du end
		end
	end
	item=items:next()
end

return(nil)
end




function BoincGetState()
local str, host, proj, task, S, P, xml_root
local state={}

state.authorized=false
state.projects={}
state.tasks={}

S=BoincConnect(server_url)
if S==nil then return nil end


Out:puts("\n~yPLEASE WAIT - UPDATING DATA FROM BOINC~0\n")
if BoincRPCAuth(S) ~= true then return state end

state.authorized=true


S:writeln("<boinc_gui_rpc_request>\n<get_state/>\n</boinc_gui_rpc_request>\n\003")
str=S:readto("\003")
S:close()

P=dataparser.PARSER("xml", str)

xml_root=P:open("/boinc_gui_rpc_reply/client_state")
state.platform=xml_root:value("platform_name")

item=xml_root:first()
while item ~= nil
do
if item:name()=="host_info" 
then 
	state.host=ParseHostInfo(item) 
	state.host.client_version=xml_root:value("core_client_major_version") .. "." .. xml_root:value("core_client_minor_version") .. "." .. xml_root:value("core_client_release")
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


item=xml_root:next()
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
Out:puts("Configure boinc@"..server_url.."~0\n")
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
	Menu:add(string.format("%30s:  %s", BoincSettingGetName(name), value), name)
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
S=BoincConnect(server_url)
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

Menu=terminal.TERMMENU(Out, 1, MENU_TOP, Out:width() -2, Out:length()-17)
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
		BoincProjectOperation(Selected, proj)
		process.sleep(1)
		boinc_state=BoincGetState()
		break;
	end

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
	
	Menu=terminal.TERMMENU(Out, 1, MENU_TOP, Out:width() - 2, 10)
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













function StartBoincLocalhost()
local pid
local connected=false

	filesys.mkdir(config.boinc_dir)
	Out:puts("~yStarting boinc~0\n")
	pid=process.xfork()
	if pid==0
	then
		process.chdir(config.boinc_dir)
		os.execute("boinc --daemon")
		--we will only get here if os.execute fails
		os.exit(0)
	else
		process.wait(pid)
		--allow time for boinc to start up

		for i=1,5,1
		do
		process.sleep(1)
		S=BoincConnect(server_url)
		if S ~= nil
		then
			Out:puts("~gConnected~0\n")
			S:close()
			process.sleep(1)
			connected=true
			break
		end

		end


		if connected == true
		then
		S=stream.STREAM(config.boinc_dir.."/gui_rpc_auth.cfg")
		if S ~=nil
		then
		config.gui_key=S:readln()
		S:close()
		SaveGuiKey()
		end
		end
			
	end


return(connected)
end



function StartBoincSSHhost()
local pid

	filesys.mkdir(config.boinc_dir)
	Out:puts("~yStarting boinc~0\n")
	pid=process.xfork()
	if pid==0
	then
		process.chdir(config.boinc_dir)
		Out:close()
		os.execute("boinc --daemon")
		process.sleep(2)
		os.exit(0)
	else
		process.wait(pid)
		S=stream.STREAM(config.boinc_dir.."/gui_rpc_auth.cfg")
		config.gui_key=S:readln()
		S:close()

		SaveGuiKey()
	end
end



function AskToStartBoinc(server_url)
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
elseif Selected=="config_acct_mgr"
then
	BoincAcctMgrConfigScreen()
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


function FormatPlatform(item)
local toks, tok 
local os=""
local arch=""

toks=strutil.TOKENIZER(item, "-|[","m")
tok=toks:next()
if tok=="x86" then arch="32"
elseif tok=="i686" then arch="32"
elseif tok=="x86_64" then arch="64"
elseif tok=="windows_x86_64" then arch="64"; os="win"
elseif tok=="windows_intelx86" then arch="32"; os="win"
elseif tok=="aarch64" then arch="arm64"
elseif tok=="arm64" then arch="arm64"
elseif tok=="arm" then arch="arm32"
elseif tok=="powerpc" then arch="ppc"
elseif tok=="e2k" then arch="e2k"
end

tok=toks:next()
tok=toks:next()
if tok=="linux" then os="lin"
elseif tok=="windows" then os="win"
elseif tok=="android" then os="and"
elseif tok=="darwin" then os="osx"
elseif tok=="freebsd" then os="bsd"
end


return os..arch
end


function FormatProjectPlatforms(proj)
local i,item
local platforms={}
local str="~r"
local sys_platform=""
local sys_alt_platform=""


sys_platform=FormatPlatform(boinc_state.platform)
if sys_platform == "lin64" then sys_alt_platform="lin32" end

for i,item in ipairs(proj.platforms)
do
platforms[FormatPlatform(item)]=""
end

for item,i in pairs(platforms)
do
if item == sys_platform or item == sys_alt_platform then str=str.." ~g"..item.."~r"
else str=str.." "..item
end

end

return str .. "~0"
end


function DisplayProjectsRunMenu(Menu, projects)
local Selected=nil
local ch, curr, str, proj, i, item

Menu:draw()
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
			Out:move(0, Out:length()-6)
			proj=projects[curr]
			if proj ~= nil 
			then
			str="~e"..proj.name.."~0 ~b"..proj.url.. "~0 ~y"..proj.type.."/"..proj.subtype.."~0 ~c "..proj.location
			str=terminal.strtrunc(str, Out:width() -2) .."~0~>\n"
			Out:puts(str)

			str=strutil.padto(proj.detail, ' ', Out:width() * 4)
			str=terminal.strtrunc(str, Out:width() * 4) .. "~>"

			--[[
			str=str.."Platforms:"
			for i,item in ipairs(proj.platforms) do str=str.." "..item end
			]]--
			Out:puts(str)
			end
		end
	end
	Out:flush()
end

return Selected
end



function DisplayProjectsMenu(selectable)
local projects, sorted, url, proj, Selected
local wid, len

Out:clear()
Out:bar("up/down/enter:select menu item   esc:back", "fcolor=white bcolor=blue")
Out:move(0,0)

if selectable == true then Out:puts("~B~wSELECT PROJECT~>~0\n")
else Out:puts("~B~wACTIVE PROJECTS~>~0\n")
end

projects=BoincGetProjectList()
if projects ~= nil
then
sorted=SortTable(projects, ProjectsSort)
wid=Out:width() - 2
len=Out:length() -10
Menu=terminal.TERMMENU(Out, 1, 2, wid, len)

for url,proj in pairs(sorted)
do
	str="~e~w" .. proj.name .. "~0 "
	str=strutil.padto(str, ' ', 32)
	if strutil.strlen(proj.descript) > 0 then str=str..  "~e~y" .. proj.descript .."~0"
	else str=str..  "~e~y" .. proj.subtype .."~0"
	end

	if strutil.strlen(str) > wid-2 then str=string.sub(str, 1, wid-2) end

	str=str.. "   " .. FormatProjectPlatforms(proj)
	Menu:add(str, proj.url)
end

if selectable==true then Menu:add("Custom Project not on official list", "custom") end

--Selected=Menu:run()
Selected=DisplayProjectsRunMenu(Menu, projects)
end

return Selected
end



function AllProjectsScreen()
DisplayProjectsMenu(false)
end


function JoinProjectScreen()

	if strutil.strlen(acct.email)==0 or strutil.strlen(acct.username)==0 or strutil.strlen(acct.pass)==0
	then
		Out:move(0,Out:height()-6)
		Out:puts("~R~w  ERROR: cannot join projects without email, username and password.\n")
		Out:puts("~R~w  Please restart and provide this information on the command line. \n")
		Out:puts("~R~w                       PRESS ANY KEY                               \n~0")
		Out:flush()
		Out:getc()
	else
		Selected=DisplayProjectsMenu(true)
		Out:clear()
		Out:move(0,0)

		if Selected == "custom"
		then 
		Out:puts("~B~wJoin 'Custom' project not on official list~>~0\n")
		Out:move(2,2)
		Selected=Out:prompt("ENTER PROJECT URL: ")
		end

		if strutil.strlen(Selected) > 0 then BoincJoinProject(Selected) end
	end
end





function DisplayHostBanner()
Out:move(0, 0)
Out:puts("~mHost:~0 ~e".. boinc_state.host.name .. "~0 ~c(" .. boinc_state.host.ip .. ")~0   ".. boinc_state.host.os .. " - " .. boinc_state.host.os_version.. "\n")
Out:puts("~mCPU:~0 " .. boinc_state.host.cpus .. "*" .. boinc_state.host.processor .. "\n")
Out:puts("~mOPS/s:~0  ~cinteger:~0 " .. strutil.toMetric(boinc_state.host.iops, 2) .. "   ~cfloating-point:~0 " .. strutil.toMetric(boinc_state.host.fpops, 2) .. "\n")
Out:puts("~mMEM:~0 " .. strutil.toMetric(boinc_state.host.mem)  .. "\n")
Out:puts("~mDISK:~0  ~ctotal:~0 " .. strutil.toMetric(boinc_state.disk_total) .. "  ~cfree:~0" .. strutil.toMetric(boinc_state.disk_free) .. "  ~cboinc usage:~0 "..strutil.toMetric(boinc_state.disk_usage) .. "\n")
Out:puts("~mBoinc Version:~0 ".. boinc_state.host.client_version .."\n")
if boinc_state.acct_mgr ~= nil and strutil.strlen(boinc_state.acct_mgr.name) > 0 
then 
	Out:puts("~mAccount Manager:~0 ".. boinc_state.acct_mgr.name .. "  " .. boinc_state.acct_mgr.url .."\n") 
else
	Out:puts("~mAccount Manager:~0 ~r~enone~0" .."\n") 
end

end


-- refresh the screen. Doesn't change any details of what's displayed (that's done in MenuSwitch and it's subfunctions)
-- but pushes all the data out to the display
function ScreenRefresh(Menu)

Out:cork()
Out:clear()
DisplayHostBanner()
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
  if boinc_state.acct_mgr ~= nil and strutil.strlen(boinc_state.acct_mgr.name) > 0 then Menu:add("update account manager", "update_acct_mgr")
	else Menu:add("configure account manager", "config_acct_mgr")
	end
	Menu:add("run benchmarks", "benchmark")
	Menu:add("shutdown boinc", "shutdown")
	Menu:add("exit app", "exit")
end


function LogFormatForDisplay(item)
local str, when

str=strutil.stripTrailingWhitespace(item:value("body"))
str=strutil.stripLeadingWhitespace(str)
when=tonumber(item:value("time"))

diff=Now-when
if diff < 60 then timestr="~ew"
elseif diff < 300 then timestr="~w"
elseif diff < 3600 then timestr="~y"
elseif diff < (3600 * 23) then timestr="~e~m"
else timestr=""
end

timestr=timestr .. time.formatsecs("%Y/%m/%d %H:%M:%S  ", when) .."~0"
str=string.format("%s %20s   %s", timestr, item:value("project"), str)

return str
end


function LogLoad(oldest, newest, project)
local selected={}
local item, str, when, diff, timestr, proj_id
local count=0

	if g_Logs==nil then g_Logs=GetLogs() end

	item=g_Logs:first()
	while item ~= nil
	do
	-- proj_id can be url or name
	proj_id=item:value("project") 
	if project==nil or project==proj_id or project==LookupProjectName(proj_id)
	then
		when=tonumber(item:value("time"))
		if when >= oldest --and when <= newest
		then
			selected[count]=item
			count=count+1
		end
	end

	item=g_Logs:next()
	end

return selected
end



function ExamineLogs(project)
local Menu

Menu=terminal.TERMMENU(Out, 1, MENU_TOP, Out:width() - 2, Out:length() -14)
Menu:add("<-- back", "back")
LogMenu(Menu, project);

Menu:run()
end


function LogMenuLoadProjects(Menu, items)
local i, item, name, value
local projects={}

for i=#items,1,-1
do
	name=LookupProjectName(items[i]:value("project"))
        projects[name]="yes"
end

for name,value in pairs(projects)
do
	if strutil.strlen(name) > 0 then Menu:add(name, "project:"..name) end
end

end


-- load up log messages from boinc, ready to be displayed
function LogMenu(Menu, project)
local items, i, item, str
local projects={}

	Now=time.secs()
	menu_tabbar="  Control   Projects   Tasks   [~eLog~0]   "

	if g_Logs==nil then g_Logs=GetLogs() end

	items=LogLoad(Now - 3600*24, 0, project)

	--Menu:add("~e~wExamine Logs~0", "examine")
	--Menu:add("--- LAST 24 Hours ---")

	-- load projects from items list, unless we are viewing one already
	if strutil.strlen(project) == 0 then LogMenuLoadProjects(Menu, items) end

	for i=#items,1,-1
	do
	str=LogFormatForDisplay(items[i])
	Menu:add(string.sub(str, 1, Out:width() -8))
	end


	return true
end




-- load up details of running tasks ready to be displayed
function TasksMenu(Menu, unsort_tasks)
local Selected, i, task, due, state_color
local tasks={}

	Now=time.secs()
	tasks=SortTable(unsort_tasks, TasksSort)
	menu_tabbar="  Control   Projects  [~eTasks~0]   Log    "
	menu_tabbar=menu_tabbar..string.format("\n   %4s %20s %6s  %7s  %8s  %8s %8s\n", "slot", "project",  "state", "percent", "cpu time", "remaining", "due")
	for i,task in pairs(tasks)
	do
		if task.slot > -1
		then
			diff=task.deadline - Now
			if diff < 0 then due="~R~w"
			elseif diff < (3600 * 24) then due="~m"
			elseif diff < (3600 * 24 * 3) then due="~y"
			else due=""
			end
			due=due .. time.formatsecs("%y/%m/%d", task.deadline) .. "~0"

			if task.state == "run" then state_color="~y"
			else state_color=""
			end

			Menu:add(string.format("%04d ~w%20s~0 %s%6s~0 %7.2f%%  %8s   %8s %8s", task.slot, string.sub(task.proj_name,1,25), state_color, task.state, task.progress * 100.0, FormatTime(task.cpu_time), FormatTime(task.remain_time), due),  task.name)
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
	
	str=string.format("\n   %20s %7s %5s %6s %6s %6s", "name", "credit",  "queue", "active", "done", "fail")

	if Out:width() > 82
	then
		str=str..string.format(" %7s  %10s  %10s", "disk use", "cred/hour", "cred/min")
	end
	menu_tabbar=menu_tabbar..str

	Menu:add("[view all projects]", "all_project")
	Menu:add("[add new project]", "new_project")
	for i,proj in pairs(projects)
	do
		str=""
		if proj.jobs_active ==0 and (proj.state=="nomore" or proj.state=="suspend")
		then 
			active="~mPAUSED~0"
		else
			if proj.jobs_active > 0 then active=string.format("~y%6d~0", proj.jobs_active)
			else active=string.format("%6d", proj.jobs_active)
			end
		end

		if strutil.strlen(proj.name)==0
		then
		str="** ADDING **   " .. proj.url
		else
		name=string.sub(proj.name, 1, 20)

		str=string.format("~w%20s~0 %7s %5d %s %6d %6d", name, strutil.toMetric(proj.host_credit),  proj.jobs_queued, active, proj.jobs_done, proj.jobs_fail)

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
function MenuSwitch(display_state)

Menu=terminal.TERMMENU(Out, 1, MENU_TOP, Out:width() - 2, Out:length() -14)
Menu:config("~C~n", "~C~e~n")
Menu:clear()
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

Menu:draw()
return Menu
end


-- Read input from the user to select items from the menus, 
-- or switch between the menus
function DisplayHostProcessMenu(display_state)
local ch, Selected

ScreenRefresh(MainMenu)
while true
do
	-- if we get a SIGWINCH signal, it means the screen has changed size, and we have to rebuild the menu
	-- to fit the new width/height of the screen
	if process.sigcheck(process.SIGWINCH)==true then MainMenu=MenuSwitch(display_state) end

	-- refresh the screen, doesn't change any details, just pushes the current screen to the terminal

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
		MainMenu=MenuSwitch(display_state)
		ScreenRefresh(MainMenu)
	elseif ch=="LEFT" or ch=="CTRL_A" 
	then 
		display_state=display_state - 1
		if display_state < 0 then display_state=0 end
		MainMenu=MenuSwitch(display_state)
		ScreenRefresh(MainMenu)
	elseif ch=="RIGHT" or ch=="CTRL_D"
	then 
		display_state=display_state + 1
		if display_state > DISPLAY_LOGS then display_state=DISPLAY_LOGS end
		MainMenu=MenuSwitch(display_state)
		ScreenRefresh(MainMenu)
        elseif ch=="\t"
	then
		display_state=display_state + 1
		if display_state > DISPLAY_LOGS then display_state=0 end
		MainMenu=MenuSwitch(display_state)
		ScreenRefresh(MainMenu)
	elseif ch ~= ""
	then
		Selected=MainMenu:onkey(ch)
		if Selected ~= nil then return Selected, display_state end
	end
	
end

end




function BoincReconnect()

boinc_state=BoincGetState()
if boinc_state==nil
then
	Out:puts("~rERROR: failed to connect to boinc at " .. server_url.."~0\n")
	if AskToStartBoinc(server_url) == true
	then 
		while boinc_state == nil
		do
		boinc_state=BoincGetState() 
		end
	else return nil
	end
elseif boinc_state.authorized == false
then
	Out:puts("~rERROR: authorization failed~0\n")
	if strutil.strlen(config.gui_key) ==0 then Out:puts("~rno authorization key supplied. Please supply it with the -key command-line option~0\n") end
	return nil
end

if boinc_state==nil then Out:puts("~rERROR: failed to connect to host~0\n"); end
return boinc_state
end


function ProcessMenus()
local display_state=0
local Selected

--sets us to the default menu
MainMenu=MenuSwitch(display_state)
while true
do
	Selected,display_state=DisplayHostProcessMenu(display_state)

	if Selected=="exit" 
	then 
		break
	elseif Selected=="new_project" then JoinProjectScreen()
	elseif Selected=="all_project" then AllProjectsScreen()

	else
		if display_state==DISPLAY_PROJECTS
		then
			DisplayProject(boinc_state.projects[Selected])
		elseif display_state==DISPLAY_TASKS
		then
			DisplayTask(boinc_state.tasks[Selected])
		elseif display_state==DISPLAY_LOGS
		then
			if Selected=="examine" then ExamineLogs("") end
			if string.sub(Selected, 1, 8)=="project:" then ExamineLogs(string.sub(Selected, 9)) end
		else
			result=ProcessControl(Selected)
			if result=="exit" then break end
		end
	end
end

end


-- this is the main interactive screen, it displays info on the boinc processes
-- running on a given host
function DisplayHost(server_url)
local host, projects, tasks, ch, mgr
local result


Out:clear()
Out:move(0,0)
Out:puts("~yConnecting to host [~0~e"..server_url.."~y]~0\n")

boinc_state=BoincReconnect(boinc_state) 
if boinc_state == nil then return end

ProcessMenus()

Out:clear()
Out:move(0,0)
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
	print("   -acct_mgr <url>     url to account manager site to use (requires -user and -pass)")
	print("   -acct_mgr none      detach from any account manager")
	print("   -save               save gui_key for url")
	print("   -debug              enable debugging: lots of stuff printed to stderr")
	print("   -d                  enable debugging: lots of stuff printed to stderr")
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
  print("To join an account manager you'll need to supply -user, and -pass arguments that supply the *account manager* credentials. These are never stored on disk.")
	
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
			config.gui_key=arg[i]
		elseif arg[i] == "-user"
		then
			i=i+1
			acct.username=arg[i]
		elseif arg[i] == "-email"
		then
			i=i+1
			acct.email=arg[i]
		elseif arg[i] == "-pass"
		then
			i=i+1
			acct.pass=arg[i]
		elseif arg[i] == "-acct_mgr"
		then
			i=i+1
			config.acct_mgr=arg[i]
		elseif arg[i] == "-save"
		then
			save_key="y"
		elseif arg[i] == "-debug" or arg[i] == "-d"
		then
			config.debug=true
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

S=stream.STREAM(config.boinc_dir.."/keys.txt","r")
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

Now=time.secs()
tempstr=process.getenv("BOINC_USERNAME")
if strutil.strlen(tempstr) > 0 then acct.username=tempstr end
tempstr=process.getenv("BOINC_EMAIL")
if strutil.strlen(tempstr) > 0 then acct.email=tempstr end
tempstr=process.getenv("BOINC_PASSWORD")
if strutil.strlen(tempstr) > 0 then acct.pass=tempstr end

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

if strutil.strlen(config.gui_key) ==0 
then 
	config.gui_key=hosts[server_url] 
elseif save_key == "y" 
then 
	SaveGuiKey() 
end



if strutil.strlen(config.acct_mgr) > 0 then BoincAcctMgrSet(config.acct_mgr, acct.username, acct.pass) end
DisplayHost(server_url) 

Out:reset()

