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
  assert(Available==true,"Faucet is not available")
  assert(not BlackList[msg.Account],"Account is in blacklist")
  assert(Supplied < Initial_Supply,"Faucet is empty")
  local member = Members[msg.User]
  assert(member == nil or member.getted == 0 or member.getted == nil,"You have got the quota")
  local order = #utils.keys(Members)
  local quota = member and member.quota or string.format("%.0f",math.max((Initial_Supply - Supplied) * 0.0001,1000000000000))
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
    if Supplied >= Initial_Supply then
      Available = false
    end
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
    Manager = Manager,
    Available = Available and "1" or "0",
    Supplied = string.format("%.0f",Supplied),
    Initial_Supply = string.format("%.0f",Initial_Supply),
    Data = {
      Members = utils.keys(Members),
      BlackList = BlackList,
      Manager = Manager,
      Available = Available,
      Supplied = Supplied,
      Initial_Supply = Initial_Supply
    }
  })
end)


-- Handlers.manualShare = function (account,amount)
--   Send({
--     Target = AGENT,
--     Action = "Add-Faucet-Quota",
--     Quantity = amount,
--     Account = account
--   }).onReply(function(m)
--     Supplied = Supplied +tonumber(m.Quantity)

--   end)

-- end

