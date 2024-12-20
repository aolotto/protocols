local drive = require("modules.drive")
local utils = require("modules.utils")
local crypto = require(".crypto")
local bint = require('.bint')(256)
local json = require("json")

local initial_state = {
  round = 1,
  bet = {0,0,0}, -- {count, amount, tickets }
  jackpot = 0,
  picks = 0,
  balance = 0,
  players = 0,
  ts_latest_draw = 0,
  ts_latest_bet = 0,
  ts_round_start = os.time(),
  ts_round_end = 0,
  run = 1,
}

local initial_stats = {
  total_players = 0,
  total_sales_amount = 0,
  total_tickets = 0,
  total_archived_round = 0,
  total_reward_amount = 0,
  total_reward_count = 0,
  total_matched_draws = 0,
  total_unmatched_draws = 0,
  ts_pool_start = os.time(),
  ts_first_bet = 0,
  ts_latest_bet = 0,
  ts_lastst_draw = 0,
  total_claimed_amount = 0,
  total_claimed_count = 0,
  total_winners = 0
}

AGENT = AGENT or ao.env.Process.Tags['Agent'] or "CoHjrI_7HL9gh36P57y6jZLwHY311ahg4I9DLlhGCew"
TOKEN = TOKEN or ao.env.Process.Tags['Token'] or "KCAqEdXfGoWZNhtgPRIL0yGgWlCDUl0gvHu8dnE5EJs"
PRICE = PRICE or 1000000
DIGITS = DIGITS or 3
DRAW_DELAY = DRAW_DELAY or 86400000
JACKPOT_SCALE = JACKPOT_SCALE or 0.5
WITHDRAW_MIN = WITHDRAW_MIN or 10
MAX_BET_COUNT = MAX_BET_COUNT or 100
TYPE = "3D"
DIVDIDEND_LIMIT = DIVDIDEND_LIMIT or 1000000000
TAX_RATE = TAX_RATE or {
  [string.format("%.0f",PRICE*1)] = 0.1,
  [string.format("%.0f",PRICE*5000)] = 0.2,
  [string.format("%.0f",PRICE*50000)] = 0.3,
  [string.format("%.0f",PRICE*500000)] = 0.4
}
TAXRATE = TAXRATE or 0.4
WAGER_DIFFICULT = WAGER_DIFFICULT or 1.1


Players = Players or {}
Bets = Bets or {}
State = State or initial_state
Numbers = Numbers or {}
Draws = Draws or {}
Leaders = {}
Funds = Funds or {0,0,0}
Taxation = Taxation or {0,0,0}
Dividends = Dividends or {0,0,0}
Buybacks = Buybacks or {0,0,0}
Stats = Stats or initial_stats
Participants = Participants or {}
Winners = Winners or {}
Sponsors = Sponsors or {}


Handlers.add("save-lotto",{
  From = AGENT,
  Action = "Save-Lotto",
  Quantity = function(quantity) return bint(quantity) >= bint(PRICE) end,
  ['X-Origin'] = TOKEN,
  Count = "%d+",
  Amount = "%d+"
},function(msg)
  assert(State.run == 1,"not accept betting at the moment")

  local count = tonumber(msg.Count) -- 用户的投注数量
  local amount = tonumber(msg.Amount) -- 用户的投注金额
  local tax = amount * TAXRATE -- 计算税收受益

  local x_numbers = msg['X-Numbers'] -- 获取用户投注的号码，如果非法则生成新的随机号码
  if #x_numbers ~= bint.tonumber(DIGITS or 3) then
    x_numbers = utils.getRandomNumber(DIGITS or 3,msg.Id)
  end

  local sponsor = msg['X-Player'] and Sponsors[msg.Sender] or nil -- 带有‘X-Player’的投注视为赞助性投注，通过msg.Sendfer获取赞助商信息
  local _player_id = msg['X-Player'] or msg.Sender  -- 获取投注者地址

  -- 更新用户投注量，如过用户列表中不存在此地址，则新建用户记录，并增加Stats中的total_players
  if not Players[_player_id] then
    Players[_player_id] = {
      bet = {0,0,0},
      win = {0,0,0},
      tax = {0,0,0},
      mine = 0,
      div = 0,
    }
    utils.increase(Stats,{total_players=1})
  end
  utils.increase(Players[_player_id].bet,{count,amount,1})
  -- 记录本轮次参与者，用户如未参加本轮则在Participants中创建用户
  if not Participants[_player_id] then
    Participants[_player_id] = {0,0,0}
    utils.increase(State,{players=1})
  end
  utils.increase(Participants[_player_id],{count,amount,1})

  -- 通过X-Mined获取用户的挖矿数据，更新挖矿信息
  if msg['X-Mined'] then
    local mining = utils.parseSting(msg['X-Mined'],",")
    if bint(mining[1]) > 0 then 
      if sponsor == nil then
        utils.increase(Players[_player_id],{mine=tonumber(mining[1])})
      else
        utils.increase(Sponsors[msg.Sender],{mined=tonumber(mining[1])})
      end  
    end
  end
  -- 更新全局状态信息及资产余额
  utils.increase(Funds,{amount,amount,0})
  utils.increase(Stats,{
    total_sales_amount = amount,
    total_tickets = 1,
  })
  utils.increase(State.bet,{count, amount, 1})
  utils.increase(State,{jackpot = amount * JACKPOT_SCALE, balance = amount})
  utils.update(State,{
    ts_latest_bet = msg.Timestamp,
    mining_quota = msg.Data.quota,
  })
  utils.update(Stats,{
    ts_latest_bet = msg.Timestamp
  })

  -- 更新税收，分红，回购帐户
  utils.increase(Taxation,{tax,tax,0})
  utils.increase(Dividends,{tax*0.5,tax*0.5,0})
  utils.increase(Buybacks,{tax*0.5,tax*0.5,0})

  -- Save the bet
  local bet = {
    id = msg['Pushed-For'],
    round = State.round,
    amount = amount,
    count = count,
    x_numbers = x_numbers,
    created = msg.Timestamp,
    player = _player_id,
    price = PRICE,
    token = TOKEN,
    ticker = Token.ticker,
    denomination = Token.denomination,
    mint = msg.Data.mint,
    sponsor = msg.Data.sponsor
  }
  table.insert(Bets,bet)

  if not BetsIndexer then BetsIndexer = {} end
  BetsIndexer[bet.id] = #Bets

  -- If the total bet amount is less than the maximum of 1000 units of bet amount or jackpot, delay the draw time
  if State.bet[2] < State.wager_limit then
    utils.update(State,{ts_latest_draw = msg.Timestamp + DRAW_DELAY})
  end

  -- log numbers
  if Numbers[x_numbers] == nil then
    utils.increase(State,{picks=1})
  end
  utils.increase(Numbers,{[x_numbers] = count})

  -- send lotto-notice
  local lotto_notice = {
    Target = msg.Sender,
    Action = "Lotto-Ticket",
    Round = string.format("%.0f", State.round),
    Count = msg.Count,
    Amount = msg.Amount,
    Price = string.format("%.0f", PRICE),
    Created = tostring(msg.Timestamp),
    Token = bet.token,
    Ticker = bet.ticker,
    Denomination = tostring(bet.denomination),
    Title = "Aolotto Ticket",
    Type = "lottery",
    ['X-Numbers'] = x_numbers,
    ['X-Mined'] = msg['X-Mined'],
    ['Pushed-For'] = bet.id or msg['Pushed-For'],
    Sponsor = bet.sponsor,
    Data = string.format([[
      <svg viewBox="0 0 400 400" fill="#DEC9FF" xmlns="http://www.w3.org/2000/svg">
        <rect width="400" height="400" fill="#DEC9FF"/>
        <rect x="20" y="20" width="360" height="360" fill="#F2F2F2" stroke="black"/>
        <text xml:space="preserve" text-anchor="start" font-size="24" y="77" x="65.58594" fill="#000">AOLOTTO TICKET</text>
        <text xml:space="preserve" style="dominant-baseline:top;text-anchor:start;font-size:120" y="243" x="63.9375" fill="#FFAC8D">%s</text>
        <text xml:space="preserve" font-size="20" stroke-width="0"  y="174" x="313.5" stroke="#000" text-anchor="end" fill="#000">X %s</text>
        <line y2="110" x2="346" y1="111" x1="61.5" stroke="#000" fill="none"/>
        <line y2="300" x2="346" y1="301" x1="58.5" stroke="#000" fill="none"/>
        <text style="dominant-baseline:top;text-anchor:start;font-size:11" y="337" x="61.5" fill="#000000">%s</text>
      </svg>
    ]],x_numbers,msg.Count,bet.id)
  }
  Send(lotto_notice)

  -- update rankings
  TopBettings = TopBettings or {}
  utils.updateRanking(TopBettings,bet.player,Players[bet.player].bet[2],50)
  TopMinings = TopMinings or {}
  utils.updateRanking(TopMinings,bet.player,Players[bet.player].mine,50)

  -- check countdown of draw
  if State.ts_latest_draw <= msg.Timestamp then Handlers.archive() end
  -- update TOKEN a
  if not TOKEN then TOKEN = msg['X-Origin'] end

end)


Handlers.add("claim","Claim",function(msg)
  local player = Players[msg.From]
  if player.win and player.win[1] - player.tax[1] >= WITHDRAW_MIN then
    if not Claims then Claims = {} end
    local claim = {
      id = msg.Id,
      amount = player.win[1],
      tax = player.tax[1],
      quantity = math.floor(player.win[1]-player.tax[1]),
      recipient = msg.Recipient or msg.From,
      player = msg.From
    }
    Claims[msg.Id] = claim
    print(claim)
    utils.decrease(Players[msg.From].win,{claim.amount,0,-claim.amount})
    utils.decrease(Players[msg.From].tax,{claim.tax,0,-claim.tax})
    Handlers.claim(claim)
  end
end)


Handlers.add("get",{Action = "Get"},{
  [{Table = "Bets"}] = function(msg)
    msg.reply({
      Total= tostring(#Bets),
      Data= utils.query(Bets,tonumber(msg.Limit) or 100,tonumber(msg.Offset) or 1,{"ts_created","desc"})
    }) 
  end,
  [{Table = "Draws"}] = function(msg)
    msg.reply({
      Total= tostring(#Draws),
      Data= utils.query(Draws,tonumber(msg.Limit) or 100,tonumber(msg.Offset) or 1,{"ts_draw","desc"})
    }) 
  end
})

Handlers.add("query",{Action="Query"},{
  [{Table = "Bets",['Query-Id']="_"}] = function(msg)
    local index = BetsIndexer[msg['Query-Id']]
    if index ~= nil then
      msg.reply({Data = Bets[index]})
    end
  end,
  [{Table = "Bets",['Query-Player']="_"}] = function(msg)
    assert(#Bets > 0, "no bets exists")
    local result = utils.filter(function(bet)
      return bet.player == msg['Query-Player']
    end,Bets)
    if #result > 0 then
      msg.reply({
        Total = tostring(#result),
        Data = result
      })
    end
  end
})

Handlers.add("get_player",{
  Action="Get-Player",
  Player="_"
},function(msg)
  assert(Players[msg.Player]~=nil,"the player does not exist")
  msg.reply({Data=Players[msg.Player]})
end)

Handlers.add("info","Info",function(msg)
  msg.reply({
    ['Name'] = Name,
    ['Token'] = TOKEN,
    ['Agent'] = AGENT,
    ['Tax'] = json.encode(TAX_RATE),
    ['Price'] = tostring(PRICE),
    ['Digits'] = tostring(DIGITS),
    ['Draw-Delay'] = tostring(DRAW_DELAY),
    ['Jackpot-Scale'] = tostring(JACKPOT_SCALE),
    ['Withdraw-Min'] = tostring(WITHDRAW_MIN),
    ['Max-Bet'] = tostring(MAX_BET_COUNT),
    ['Pool-Type'] = TYPE,
    ['Token-Ticker'] = Token and Token.ticker,
    ['Token-Denomination'] = Token and tostring(Token.denomination),
    ['Token-Logo'] = Token and Token.logo
  })
end)

Handlers.add("state","State",function(msg)
  msg.reply({ Data=State})
end)

Handlers.add("stats","Stats",function(msg)
  local stats = Stats
  stats.taxation = Taxation
  msg.reply({ Data=stats})
end)

Handlers.add("ranks","Ranks",function(msg)
  local ranks = {
    bettings = TopBettings,
    winnings = TopWinnings,
    minings = TopMinings,
    dividends = TopDividends
  }
  msg.reply({ Data=ranks})
end)

Handlers.add("get",{Action = "Get"},{
  [{Table = "Bets"}] = function(msg)
    msg.reply({
      Total= tostring(#Bets),
      Data= utils.query(Bets,tonumber(msg.Limit) or 100,tonumber(msg.Offset) or 1,{"created","desc"})
    }) 
  end,
  [{Table = "Draws"}] = function(msg)
    msg.reply({
      Total= tostring(#Draws),
      Data= utils.query(Draws,tonumber(msg.Limit) or 100,tonumber(msg.Offset) or 1,{"ts_draw","desc"})
    }) 
  end
})

Handlers.add("query",{Action="Query"},{
  [{Table = "Bets",['Query-Id']="_"}] = function(msg)
    local index = BetsIndexer[msg['Query-Id']]
    if index ~= nil then
      msg.reply({Data = Bets[index]})
    end
  end,
  [{Table = "Bets",['Query-Player']="_"}] = function(msg)
    assert(#Bets > 0, "no bets exists")
    local result = utils.filter(function(bet)
      return bet.player == msg['Query-Player']
    end,Bets)
    if #result > 0 then
      msg.reply({
        Total = tostring(#result),
        Data = result
      })
    end
  end
})

Handlers.add("Cron",function(msg)
  if msg.Timestamp >= State.ts_latest_draw and State.ts_latest_draw > 0 and #Bets > 0 then
    Handlers.archive()
  end
  if Handlers.distribute and Dividends[1] >= DIVDIDEND_LIMIT then
    Handlers.distribute(Dividends[1])
  end
end)


Handlers.archive = function()
  if not Archive then
    assert(#Bets >=1,"bets length must greater than 1.")
    assert(State.jackpot >= 1,"jackpot must greater than 1.")
    assert(State.ts_latest_draw > 0 and State.ts_latest_draw <= os.time(), "Not yet time for lottery draw")
    State.ts_round_end = os.time()
    Archive = {
      state = utils.deepCopy(State),
      bets = utils.deepCopy(Bets),
      numbers = utils.deepCopy(Numbers),
      participants = utils.deepCopy(Participants)
    }
    Bets = {}
    Numbers = {}
    Participants = {}
    BetsIndexer = {}
    local balance = State.balance - State.jackpot
    local jackpot = balance * JACKPOT_SCALE
    local wager_limit = math.max(State.wager_limit + jackpot, PRICE * 10 ^ DIGITS )
    local round = State.round + 1
    utils.update(State,{
      picks = 0,
      bet = {0,0,0},
      players = 0,
      ts_round_start = os.time(),
      ts_latest_bet = 0,
      round = round,
      balance = balance,
      jackpot = jackpot,
      wager_limit = wager_limit,
      ts_round_end = 0,
      ts_latest_draw = 0
    })
    print("Round switch to "..State.round)

    Handlers.once("_once_archive_"..Archive.state.round,{
      From = AGENT,
      Action = "Archived",
      Round = tostring(Archive.state.round)
    },function(m)
      print("The round ["..m.Round.."] has been archived as: "..m['Archive-Id'])
      Archive.id = m['Archive-Id']
      Archive.block_height = m['Block-Height']
      Archive.time_stamp = m.Timestamp
      utils.increase(Stats,{
        total_archived_round = 1,
      })
      utils.update(State,{mining_quota = m.Data.quota})
      Handlers.draw(Archive)
    end)

    Send({
      Target = AGENT,
      Action = "Archive",
      Round = tostring(Archive.state.round),
      Data = Archive.state
    })
  else
    Handlers.draw(Archive)
  end
end

Handlers.draw = function(archive)
  local archive_id = archive.id
  local state = archive.state or Archive.state
  local bets = archive.bets or Archive.bets
  local numbers = archive.numbers or Archive.numbers
  local latest_bet = bets[#bets]
  local block = drive.getBlock(archive.block_height or 1520692)
  local seed = block.hash ..'_'..archive_id
  local lucky_number = utils.getDrawNumber(seed,DIGITS or 3)
  local jackpot = state.jackpot
  
  

  print("lucky_number:"..lucky_number)
  
  local matched = numbers[lucky_number] or 0
  local reward_type = matched > 0 and "MATCHED" or "FINAL_BET"
  local taxation, tax_rate = Handlers.computeTaxation(jackpot,matched > 0 and "AUTO" or "MAX")
  print(jackpot.."-"..taxation.."-"..tax_rate)

 

  -- fetch rewards
  local rewards = {}
  if matched > 0 then
    local _share = jackpot / matched
    for i,bet in ipairs(bets) do
      if bet.x_numbers == lucky_number then
        utils.increase(rewards,{[bet.player]=bet.count * _share})
      end
    end
  else
    rewards[latest_bet.player] = jackpot
  end

  -- count winners and send Win-Notice to user
  local winners = 0
  for _player,_prize in pairs(rewards) do
    winners = winners + 1
    if not Players[_player].win then 
      Players[_player].win = {0,0,0} 
    end
    if not Players[_player].tax then
      Players[_player].tax = {0,0,0} 
    end
    if not Winners[_player] then 
      Winners[_player] = {0,0}
      utils.increase(Stats,{total_winners=1})
    end
    utils.increase(Players[_player].win,{_prize,_prize,0})
    utils.increase(Winners[_player],{1,_prize})
    local _tax = _prize * tax_rate
    utils.increase(Players[_player].tax,{_tax,_tax,0})
    TopWinnings = TopWinnings or {}
    utils.updateRanking(TopWinnings,_player,Players[_player].win[2],50)
    local win_notice = {
      Target = _player,
      Action = "Win-Notice",
      Prize = string.format("%.0f",_prize),
      Tax = tostring(_tax),
      Round = string.format("%.0f", state.round),
      Archive = archive_id,
      Token = TOKEN or Token.id,
      Ticker = Token.ticker,
      Denomination = tostring(Token.denomination),
      Jackpot = string.format("%.0f", state.jackpot),
      ['Tax-Rate'] = tostring(tax_rate),
      ['Lucky-Number'] = tostring(lucky_number),
      ['Reward-Type'] = reward_type,
      Created = tostring(archive.time_stamp or os.time()),
      Data = Players[_player]
    }
    Send(win_notice)
  end

  -- save latest draw to global Draws table
  local draw =  {
    round = state.round,
    lucky_number = lucky_number,
    players = state.players,
    jackpot = jackpot,
    rewards = rewards,
    archive = archive_id,
    winners = winners,
    matched = matched,
    reward_type = reward_type,
    created = archive.time_stamp,
    bet = state.bet,
    block_hash = block.hash,
    taxation = taxation,
    token = Token,
  }

  -- increase global taxation and updating the stats
  -- utils.increase(Taxation,{taxation,taxation,0})
  utils.increase(Stats,{
    total_unmatched_draws = matched > 0 and 0 or 1,
    total_matched_draws = matched > 0 and 1 or 0,
    total_reward_count = winners,
    total_reward_amount = jackpot
  })
  utils.update(Stats,{
    ts_lastst_draw = draw.created
  })

  local draw_notice = {
    Target = ao.id,
    Action = "Draw-Notice",
    Round = string.format("%.0f", draw.round),
    Players = string.format("%.0f", draw.players),
    Jackpot = string.format("%.0f", draw.jackpot),
    Winners = string.format("%.0f", draw.winners),
    Matched = string.format("%.0f", draw.matched),
    Archive = draw.archive or archive_id,
    Token = TOKEN or Token.id,
    Ticker = Token.ticker,
    Taxation = tostring(taxation),
    Denomination = tostring(Token.denomination),
    Created = tostring(archive.time_stamp or os.time()),
    ['Lucky-Number'] = tostring(draw.lucky_number),
    ['Reward-Type'] = reward_type,
    Bet = table.concat(state.bet,","),
    Data = draw
  }

  Handlers.once("once_draw_notice_of_"..draw_notice.Archive,{
    Action = "Draw-Notice",
    Round = draw_notice.Round,
    Archive = draw_notice.Archive
  },function(msg)
    table.insert(Draws,{round=msg.Round,id=msg.Id,archive=msg.Archive})
    Archive = nil
    print("Finish drawing for round " .. msg.Round .. " : "..msg.Id)
  end)
  print("Sending draw notice...")
  Send(draw_notice)
end


Handlers.fetchTokenInfo = function(token)
  token = token or TOKEN
  if token~=nil and type(token)=="string" then
    Handlers.once("once_get_tokeninfo_"..token,{
      From = token,
      Name = "_",
      Ticker = "_",
      Logo = "_",
      Denomination = "_"
    },function(m)
      Token = {
        id = m.From,
        name = m.Name,
        ticker = m.Ticker,
        denomination = tonumber(m.Denomination),
        logo = m.Logo,
      }
      print("Token info updated.")
    end)
    Send({Target=token,Action="Info"})
  end
end

if not Token then
  local token_id = TOKEN or ao.env.Process.Tags.Token
  if token_id then 
    Handlers.fetchTokenInfo(token_id) 
  end
end

Handlers.pushLeaderBets = function(player,amount)
  local new_leader_bets = table.pack(table.unpack(Leaders.bet))
  local included = 0
  for i,v in ipairs(new_leader_bets) do
    if v[1] == player then
      included = 1
      new_leader_bets[i] = {player,amount}
    end
  end

  if included == 0 then
    new_leader_bets = utils.concat(new_leader_bets,{{player,amount}})
  end

  if #new_leader_bets > 1 then
    table.sort(new_leader_bets, function(a, b) return a[2] > b[2] end)
  end
  if #new_leader_bets > 20 then
    for i = 21, #new_leader_bets do
      table.remove(new_leader_bets, 21)
    end
  end
  Leaders.bet = new_leader_bets

end

Handlers.computeTaxation = function(jackpot,type)
  local rate = 0.4
  -- if type ~= "MAX" then
  --   for k,v in pairs(TAX_RATE) do
  --     if tonumber(k) <= jackpot then
  --       rate = math.max(v,rate)
  --     end
  --   end
  -- else
  --   rate = 0.4
  -- end
  return math.floor(jackpot * rate) , rate
end



Handlers.reset = function(...)
  State = initial_state
  Stats = initial_stats
  Bets = {}
  Players = {}
  Draws = {}
  Leaders = {}
  Numbers = {}
  Funds = {0,0,0}
  Taxation = {0,0,0}
  Participants = {}
end

Handlers.claim = function(claim)
  Handlers.once('once_claimed_'..claim.id,{
    Action = "Debit-Notice",
    From = AGENT,
    Recipient = claim.recipient,
    ['X-Origin'] = TOKEN,
    ['X-Player'] = claim.player,
    ['X-Transfer-Type'] = "Claim-Notice",
    ['X-Claim-Id'] = claim.id,
    Quantity = tostring(claim.quantity)
  },function(m)
    local _qty = tonumber(m.Quantity)
    local _tax = tonumber(m['X-Tax'])
    Claims[m['X-Claim-Id']] = nil
    utils.decrease(Funds,{_qty,0,-_qty})
    utils.increase(Stats,{
      total_claimed_count = 1,
      total_claimed_amount = tonumber(m['X-Amount'])
    })
  end)
  Send({
    Target = AGENT,
    Action = "Claiming",
    ['X-Amount']=tostring(claim.amount),
    ['X-Tax']=tostring(claim.tax),
    ['X-Player']=claim.player,
    ['X-Transfer-Type'] = "Claim-Notice",
    ['X-Claim-Id'] = claim.id,
    ['X-Pool'] = ao.id,
    ['Pushed-For'] = claim.id,
    Quantity=tostring(claim.quantity),
    Recipient = claim.recipient
  })
end




if AGENT and TOKEN then
  ao.addAssignable(AGENT,{From=AGENT})
  ao.addAssignable(TOKEN.."-Debit-Notice",{From=TOKEN,Action = "Debit-Notice"})

  -- 分红
  Handlers.distribute = function(amount)
    assert(Dividends[1] >= DIVDIDEND_LIMIT ,"Distribution amount must be greater than 1")
    local _amount = amount or Dividends[1]

    utils.increase(Dividends,{_amount,_amount,0})
    if not DIV_REF then DIV_REF = 1 end
    local dis_message = {
      Target = AGENT,
      Action = "Distribute",
      Amount = string.format("%.0f",_amount),
      Token = TOKEN,
      Denomination = tostring(Token.denomination),
      Ticker = Token.ticker,
      ['Distribution-Ref'] = tostring(DIV_REF)
    }
    Send(dis_message).onReply(function(msg)
      local _dis_amount = tonumber(msg.Amount)
      utils.decrease(Taxation,{_dis_amount,0,-_dis_amount})
      utils.decrease(Dividends,{_dis_amount,0,-_dis_amount})
      utils.decrease(Funds,{_dis_amount,0,-_dis_amount})
      utils.increase(Stats,{
        total_distribute_count = 1,
        total_distribute_amount = _dis_amount
      })
      DIV_REF = DIV_REF + 1
    end)
  end

  -- 记录用户分红
  Handlers.add("log-user-div",{
    From = TOKEN,
    Target = AGENT,
    Action = "Debit-Notice",
    ['X-Transfer-Type'] = "Distribution",
    ['X-Distribution-From'] = ao.id
  },function(msg)
    if Players[msg.Recipient] then
      utils.increase(Players[msg.Recipient],{div=tonumber(msg.Quantity)})
      TopDividends = TopDividends or {}
      utils.updateRanking(TopDividends,msg.Recipient,Players[msg.Recipient].div,50)
    end
  end)

  -- 回购
  Handlers.buyback = function(amount)
    if not BUYBACK_REF then BUYBACK_REF = 1 end
    print("do buyback")
  end


end




Handlers.addSponsor = function(id,name,desc,url)
  if not Sponsors[id] then
    Sponsors[id] = {}
  end
  utils.update(Sponsors[id],{
    id = id,
    name = name or Sponsors[id].name,
    desc = desc or Sponsors[id].desc,
    url = url or Sponsors[id].url
  })
  print("Sponsor added!")
end