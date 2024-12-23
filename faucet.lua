-- local const = require("modules.const")
local utils = require(".utils")

if not AGENT then AGENT = '<AGENT>' end
if not Manager then Manager = Owner end
if not Members then Members = {} end
if not Initial_Supply then Initial_Supply = 21000000000000000000 end
if not Supplied then Supplied = 0 end
if not BlackList then BlackList = {} end
if not Available then Available = true end

Handlers.add("share",{
  Action="Share",
  From = function (_from)
    return _from == Manager or _from == Owner
  end,
  User = function (_user)
    return Members[_user] == nil or Members[_user].getted == 0
  end,
  Account = function(_account)
    return #_account == 43 and _account~= Manager and _account~= Owner
  end
},function(msg)
  local member = Members[msg.User]
  local order = #utils.keys(Members)
  local quota = member and member.quota or string.format("%.0f",(Initial_Supply - Supplied) * 0.0001)
  Members[msg.User] = {
    user_id = msg.User,
    user_address = msg.Account,
    msg_id = msg.Id,
    eval_id = msg.Tags['Pushed-For'],
    quota = quota,
    timestamp = msg.Timestamp,
    order = tostring((order or 0)+1),
    getted = 0
  }

  Supplied = Supplied + tonumber(quota)
  
  Send({
    Target = AGENT,
    Action = "Add-Faucet-Quota",
    Quantity = quota,
    Account = msg.Account,
    ['X-Faucet-Order'] = tostring((order or 0)+1),
    User = msg.User
  }).onReply(function(m)
    Members[m.User].getted = tonumber(m.Quantity)
  end)

end)

Handlers.add("get_member_balance",{
  Action = "GetMemberBalance",
  User = "_"
},function(msg)
  msg.reply({Data=Members[msg.User]})
end)

Handlers.add("info","Info",function(msg)
  msg.reply({
    Name= Name or "Aolotto-Faucet",
    Manager = Manager
  })
end)