--!strict
-- ReplicatedStorage/Shared/Conversations.lua
-- WHAT YOU SAY TO THEM (the hundred-and-fourth pass, your idea: "when I talk to the characters, I want to say the
-- lines to them myself, and I can choose not to talk to them by simply walking away from them far enough that the
-- options of what to say disappear by themselves"). Talk to someone (F) and up to MOST things you could say come up;
-- choose one and you say it, over your own head for anyone near to see, and they answer. Walk away, further than
-- REACH, and the choices go. What you have said is kept in your save, so nobody is asked the same thing twice and
-- the story goes on where you left it.
--
-- AND WHAT IT IS ALL ABOUT (you chose it: "You are Marsh's child"). Everyone in Harrow Bay half recognises you;
-- "you've got his face". They mean it. The key holder before you was EDWIN MARSH, who went down to open the gates in
-- 1979 and got them open, and the Hold kept him for it. He left a child at Hill House, about Pip's age, who sat on the
-- sea wall every night waiting for him. That child is you. The faceless one on the Deco tower is him, still waiting
-- for you to come down. You took the key home on the 13th and could not make yourself go in, because of what it
-- cost him. Nobody says it outright: it comes in pieces, a CLUE at a time, from whoever you ask the right thing, and
-- each piece goes in your journal (NOTES). Pip is you, thirty years ago, and Tobi is your father: open the gates, or
-- she waits as you did.
--
-- A TOPIC: `say` is your line; `reply` what they answer, line after line; `after` another topic that has to have been
-- said first (anyone's); `needs` a clue you have to have; `clue` the one this one gives you. SMALLTALK, offered last
-- every time, is their next ordinary line (Townsfolk.LINES). No dashes anywhere (check_story.py).

local Conversations = {}

export type Topic = { id: string, say: string, reply: { string }, after: string?, needs: string?, clue: string? }

Conversations.MOST = 3 -- choices on the screen at once
Conversations.REACH = 16 -- studs: further than this from them and the choices go
Conversations.SMALLTALK = "How are you keeping?"

Conversations.TOPICS = {
	-- LEVEL 1, CITY SHORE, 9:14 in the morning.
	Sal = {
		{ id = "sal_who", say = "Who's this key holder everyone's on about?", reply = {
			"Whoever's on call at the waterworks, love. Gets the key to Outfall 3 and takes it home of a night.",
			"This week it's the one from Hill House. Up on the hill, with the big clock.",
		} },
		{ id = "sal_hill", say = "What's at Hill House?", after = "sal_who", clue = "face", reply = {
			"The Marsh house. The big clock in the hall stopped years back, and nobody's had it going since.",
			"Funny. You've the look of them, you know. The Marsh look.",
		} },
		{ id = "sal_siren", say = "What's the siren for?", reply = {
			"Council says it's a test. Mr Pell sounds it at twelve, and again at midnight.",
			"The midnight one isn't a test. Nobody says so. Everybody knows.",
		} },
		{ id = "sal_dad", say = "Did you know my dad?", needs = "father", reply = {
			"Edwin? Course I did. Bought a ninety-nine every Sunday and gave you the flake.",
			"You'd sit on that wall waiting for him. Every night, after. I'd bring you a cone.",
		} },
	},
	Pip = {
		{ id = "pip_dad", say = "Where's your dad gone?", reply = {
			"Down to find the key man. He took his red towel.",
			"He said he'd be back before the siren. The siren's been twice.",
		} },
		{ id = "pip_castle", say = "What are you building?", reply = {
			"A castle for when Dad gets back. With a moat, so the sea can't get it.",
			"The sea gets it anyway. Then I build it again.",
		} },
		{ id = "pip_scared", say = "Aren't you scared?", reply = {
			"No. Mum says the water's scared of the gates.",
			"Are you scared? You look scared.",
		} },
		{ id = "pip_same", say = "My dad went down there too. A long time ago.", needs = "father", reply = {
			"Did he come back?",
			"Oh.",
			"Then you go and get mine. Before he forgets the way back.",
		} },
	},
	Maren = {
		{ id = "maren_late", say = "Late for what?", reply = {
			"For the gates. You're on call. You've been on call for three days.",
			"The whole bay's held up behind them, waiting on your key.",
		} },
		{ id = "maren_pell", say = "Who's Mr Pell?", reply = {
			"The siren keeper. Lives in the tower in the middle there. Sounds it every midnight since the eleventh.",
			"Nobody's seen him come out. You'd think he was waiting for someone.",
		} },
		{ id = "maren_dive", say = "Did you ever see Marsh go off this board?", needs = "marsh", clue = "ribbon", reply = {
			"I was a girl. He went off here in '79 with the key round his neck on a green ribbon.",
			"He waved at someone up on the sea wall. A little one. Then he went in.",
		} },
	},
	-- LEVEL 2, THE SKY POOLS, three in the afternoon.
	Dev = {
		{ id = "dev_list", say = "What other list am I on?", reply = {
			"The one down at the pumps. Who's on call. Yours is the name at the top.",
			"Mine's not on any list. That's why I'm up here having a lovely time.",
		} },
		{ id = "dev_soft", say = "Why has everything up here gone soft?", reply = {
			"Held too long, mate. Anything held too long goes soft.",
			"Like a bar of soap in a hot hand.",
		} },
		{ id = "dev_marsh", say = "Was Edwin Marsh ever on your list?", needs = "marsh", reply = {
			"Before my time. My dad ran this bar then. Said Marsh had a drink up here the night before he went down.",
			"Lemonade. Said he had a little one at home and wanted a clear head in the morning.",
		} },
	},
	Okafor = {
		{ id = "okafor_seat", say = "Who's the seat for?", reply = {
			"My Tobi. He went to find the man with the keys.",
			"He promised he'd be back by three. It's always nearly three.",
		} },
		{ id = "okafor_face", say = "Whose face have I got?", after = "okafor_seat", clue = "marsh", reply = {
			"The key man's. Edwin Marsh. You've his eyes and his chin and that worried look.",
			"He had that look the night he went down. Nobody's seen it since. Until you.",
		} },
		{ id = "okafor_pip", say = "Pip's waiting for him too.", reply = {
			"She won't leave that sandcastle. Says if she leaves, he won't know where to come back to.",
			"Children wait better than we do.",
		} },
	},
	Rudy = {
		{ id = "rudy_song", say = "What's this song called?", reply = {
			"Nobody knows. It was on when the street went under, so it's the song now.",
			"Every time it ends, it starts. I've stopped minding.",
		} },
		{ id = "rudy_under", say = "What's under the pumps?", reply = {
			"Ask the key man. He'd know. He's the only one who's meant to go down there.",
		} },
	},
	-- LEVEL 3, THE SUNKEN CITY, eight minutes to midnight.
	Attendant = {
		{ id = "att_tap", say = "Why can't I tap the glass?", reply = {
			"Because something taps back.",
			"It started the night the clocks stopped. Very politely, at first.",
		} },
		{ id = "att_staff", say = "Where did the rest of the staff go?", reply = {
			"Down to the Corporation Baths. Warmest place in town. Nobody's come back up to say.",
		} },
		{ id = "att_marsh", say = "Did a man called Marsh ever come in here?", needs = "marsh", reply = {
			"Years back. He'd stand at that window and look down for a long while.",
			"He said the gates were his to open. He said it like it frightened him.",
		} },
	},
	Fisherman = {
		{ id = "wick_hold", say = "What do you call this, the Hold?", reply = {
			"The water held behind the gates, and the day held with it.",
			"Some of us were here last time. We know the word.",
		} },
		{ id = "wick_key", say = "You held the key yourself?", clue = "marsh", reply = {
			"Forty years back. Opened the gates on time and gave the key back. That's the job.",
			"The one after me was Marsh. He never gave it back.",
		} },
		{ id = "wick_marsh", say = "What happened to Marsh?", needs = "marsh", reply = {
			"Went down to open them in '79. Got them open, too. The Hold kept him for it.",
			"Left a little one up at Hill House. About Pip's age, then.",
		} },
		{ id = "wick_you", say = "Why are you looking at me like that?", after = "wick_marsh", clue = "father", reply = {
			"Because you're the little one, aren't you. Marsh's.",
			"You've got his face. While he still had one.",
		} },
		{ id = "wick_tower", say = "The one up on the tower. Is that him?", needs = "father", clue = "watcher", reply = {
			"Don't stare at him, love. He's been waiting a long time for you to come down.",
			"Open the gates, and maybe he can stop waiting.",
		} },
	},
	-- LEVEL 4, THE CORPORATION BATHS, four minutes to midnight.
	Venn = {
		{ id = "venn_ticket", say = "One ticket, please.", reply = {
			"That'll be tuppence. Mind the floors, they're wet.",
			"Everyone who came down for you had a ticket. Nobody wanted a return.",
		} },
		{ id = "venn_staff", say = "What's behind the staff door?", after = "venn_ticket", reply = {
			"The back rooms, dear. Staff only.",
			"Something walks back there that used to be staff. Don't let it catch you lost.",
		} },
		{ id = "venn_marsh", say = "Did Edwin Marsh come through here?", needs = "marsh", clue = "ribbon", reply = {
			"Bought a ticket in '79. The last one he ever bought.",
			"His coat's still in lost property, with a green ribbon in the pocket. Nobody's come for it.",
		} },
	},
	Tobi = {
		{ id = "tobi_three", say = "It's not three. It's nearly midnight.", reply = {
			"Is it? Oh no. Oh, she'll be cross.",
			"The halls are longer every time. I keep coming back to the same corner.",
		} },
		{ id = "tobi_pip", say = "Pip's still building her sandcastle.", reply = {
			"Course she is.",
			"Tell her I'm nearly there. Tell her the moat wants to be deeper.",
		} },
		{ id = "tobi_you", say = "My dad went down here too.", needs = "father", reply = {
			"Marsh. You're Marsh's.",
			"Then you know what it's like up there, waiting. Don't make her wait like you did. Open them.",
		} },
	},
	Barlow = {
		{ id = "barlow_engines", say = "Can't you open the gates?", reply = {
			"I can start the engines. The gates take the key, and the key goes home with the key holder.",
			"That's you. It was always going to be you.",
		} },
		{ id = "barlow_card", say = "My card's not clocked in.", reply = {
			"No. Clock in, open the gates, and the bay goes out. That's all the job is.",
		} },
		{ id = "barlow_marsh", say = "Tell me about my father.", needs = "father", clue = "price", reply = {
			"He stood right where you're standing. I told him the same as I'm telling you.",
			"He got them open. The bay went out on time. And the Hold kept him for it.",
		} },
		{ id = "barlow_why", say = "Is that why I never came in?", needs = "price", reply = {
			"I'd say so. Nobody blames you.",
			"But the bay can't go out without you. And neither can he.",
		} },
	},
	-- LEVEL 5, HILL HOUSE, eight in the morning (first in the story's clock). Asked again on a later visit, once you
	-- know whose child you are, each of them has one more thing to say.
	Gale = {
		{ id = "gale_order", say = "You still bring his milk?", reply = {
			"Every morning since '79. The order never got stopped, and I never asked anyone to stop it.",
			"Two pints. One for him and one for the little one.",
		} },
		{ id = "gale_station", say = "What does the station want me for?", reply = {
			"Outfall 3. The tide's held up behind the gates and only the key opens them.",
			"Barlow can start the engines. He can't do your bit.",
		} },
		{ id = "gale_clock", say = "Why did the big clock stop?", after = "gale_order", clue = "clock", reply = {
			"The night he went down. Four minutes to midnight, and nobody's had it going since.",
			"Some mornings I'd swear I hear it ticking from the step. Then I listen, and it isn't.",
		} },
		{ id = "gale_little", say = "The second pint was for me, wasn't it.", needs = "father", reply = {
			"It was, love. Thirty years. I never could stop leaving it.",
			"Go and do what he did. Then come back up, and drink it.",
		} },
	},
	Dunn = {
		{ id = "dunn_paper", say = "What does the paper say about me?", reply = {
			"Key holder this week, Outfall 3, and the house. Your name in big letters.",
			"They put his name in the same place, once. Same letters.",
		} },
		{ id = "dunn_door", say = "Why is the door green?", reply = {
			"He painted it the week he got the key. Said a key holder's door ought to be found in the dark.",
			"The same green as the ribbon he kept it on. Nobody remembers that but me.",
		} },
		{ id = "dunn_wall", say = "Did you ever see me on the sea wall?", needs = "father", reply = {
			"Every evening, on my way home. A little one in a big coat, looking out.",
			"I'd say goodnight and you'd never look round. You were watching the water for him.",
		} },
	},
}

-- WHAT EACH CLUE PUTS IN YOUR JOURNAL (a note), the first time you learn it.
Conversations.NOTES = {
	face = { title = "The Marsh look", from = "Sal, on the Front",
		body = "Sal says I have the Marsh look. The Marshes of Hill House, with the big clock." },
	marsh = { title = "Edwin Marsh",
		body = "The key holder for Outfall 3 before me. Went down to open the gates in 1979, and did not come back up." },
	ribbon = { title = "The green ribbon",
		body = "He wore the key round his neck on a green ribbon. His coat is still in the baths' lost property, the "
			.. "ribbon in its pocket." },
	father = { title = "My father", from = "Mr Wick, on the pier",
		body = "Edwin Marsh was my father. The little one who waited on the sea wall every night was me." },
	watcher = { title = "The one on the tower", from = "Mr Wick, on the pier",
		body = "The faceless one on the Deco tower is my father. He has been waiting a long time for me to come down." },
	price = { title = "What it cost him", from = "Mr Barlow, at the flume",
		body = "He got the gates open, and the bay went out on time. The Hold kept him for it. That is why I never came in." },
	-- Written by the time clock at the flume, not by anyone's answer (Townsfolk.write).
	clocked = { title = "Clocked in", from = "The time clock, at the flume",
		body = "14 August, three minutes to midnight. My card in the clock, and its mark on it. On shift." },
	clock = { title = "His clock", from = "Mr Gale, at the top of the hill",
		body = "The big clock in the hall at Hill House stopped at four minutes to midnight the night he went down, in "
			.. "1979. Nobody has had it going since." },
}

-- What `name` can be asked now, by someone who has said and learned what is in `known` (topic ids, and "clue:" ids),
-- in the order written, MOST at the most (SMALLTALK is added after these by the caller). With `saidNow`, what has been
-- said to them in this run of the level (the hundred-and-twenty-third pass, from your test: "the talk with characters
-- does not reset, which should happen"), a topic said only in an earlier run comes back; what was learned stays in
-- `known`, so a topic waiting on another said in any run is offered at once.
function Conversations.offered(name: string, known: { [string]: boolean }, saidNow: { [string]: boolean }?): { Topic }
	local out = {}
	local said = saidNow or known
	for _, topic in ipairs((Conversations.TOPICS :: any)[name] or {}) do
		local ready = not said[topic.id]
			and (topic.after == nil or known[topic.after] == true)
			and (topic.needs == nil or known["clue:" .. topic.needs] == true)
		if ready then
			table.insert(out, topic)
			if #out >= Conversations.MOST then
				break
			end
		end
	end
	return out
end

-- A topic of `name`'s by its id, or nil.
function Conversations.topic(name: string, id: string): Topic?
	for _, topic in ipairs((Conversations.TOPICS :: any)[name] or {}) do
		if topic.id == id then
			return topic
		end
	end
	return nil
end

Conversations.STAMP = "3ea9ed08"
return Conversations
