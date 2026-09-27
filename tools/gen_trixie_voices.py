#!/usr/bin/env python3
"""Auto-generate Trixie's voice lines with ElevenLabs (voice: Arabella).

Outputs .mp3 straight into Sounds\\Trixie\\ (WoW plays mp3; the addon tries
.ogg first then .mp3). Stdlib only - no pip installs, no ffmpeg.

Filenames follow the count-based scheme the addon expects: trix_<category><n>
(e.g. trix_win1.mp3 ... trix_win28.mp3).

BATCHED / QUOTA-SAFE GENERATION
  The POOLS below are the *target* line set (we're growing toward ~10x over
  several months of ElevenLabs budget). A run only generates what's MISSING,
  frequent categories FIRST, and each category fills its indices 1..N in
  order - so if the monthly character budget runs out mid-run, every category
  is still contiguous from 1 (no gaps). After each batch, sync the Lua table
  to what actually landed on disk:

    python tools/gen_trixie_voices.py --counts-disk   # -> paste into Lobby.TRIXIE_VOICE

  NEVER set Lobby.TRIXIE_VOICE from --counts (the target); use --counts-disk
  (the achieved) so PlayTrixieVoice's math.random(1,N) never picks a missing
  clip.

USAGE
  set ELEVENLABS_API_KEY=sk_...        (PowerShell: $env:ELEVENLABS_API_KEY="sk_...")
  python tools/gen_trixie_voices.py            # generate everything MISSING (freq first)
  python tools/gen_trixie_voices.py --force    # regenerate ALL (overwrites)
  python tools/gen_trixie_voices.py --only win,open_crash   # subset by category
  python tools/gen_trixie_voices.py --counts        # target counts (POOLS lengths)
  python tools/gen_trixie_voices.py --counts-disk   # ACHIEVED counts (files on disk) -> Lua
  python tools/gen_trixie_voices.py --list-voices
  python tools/gen_trixie_voices.py --dry-run
"""
import argparse, json, os, re, sys, time, urllib.request, urllib.error

API = "https://api.elevenlabs.io/v1"
VOICE_NAME = "Arabella"
MODEL_ID = "eleven_multilingual_v2"
OUTPUT_FORMAT = "mp3_44100_128"
VOICE_SETTINGS = {"stability": 0.45, "similarity_boost": 0.75,
                  "style": 0.35, "use_speaker_boost": True}

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Sounds", "Trixie")

# category -> list of lines. Filenames become trix_<category><1..N>. Persona:
# sassy Southern-belle casino host - warm, teasing, a little conspiratorial.
# DICT ORDER = generation priority (most-heard categories first) so a
# budget-limited run spends its clips where players notice variety most.
POOLS = {
    "greet": [
        "Well look who's back! Pull up a chair, sugar, the felt's still warm.",
        "There's my favorite high roller. Let's go make some bad decisions.",
        "Welcome to Chairface's, hon. The tables are hot tonight.",
        "Doors are open, drinks are flowin'. Pick your poison off the board.",
        "Evenin', sugar. The house always wins... but tonight it could be your house.",
        "Back for more punishment? I do admire your spirit, darlin'.",
        "Step on in, hon. Luck's a lady and she's been askin' about you.",
        "Ah, a familiar face! Wallet feelin' heavy? Let's fix that.",
        "Welcome back to the finest den of iniquity in Azeroth, sugar.",
        "Come in, come in! The dice are warm and the cards are fair. Mostly.",
        "Look what the wind blew in. Missed you at the tables, darlin'.",
        "Well don't you clean up nice. Come lose it all in style, sugar.",
        "Heya, high roller. Kept your usual seat warm and everything.",
        "The chandeliers are lit and the cards are shuffled just for you, hon.",
        "Welcome, welcome. Leave your good sense at the door, sweetheart.",
        "There you are! I was startin' to think you'd found an honest hobby.",
        "Come on in from the cold, sugar. It's always warm where the gold flows.",
        "Evenin', gambler. Feelin' brave, or just feelin' generous?",
        "Pull up a stool, darlin'. First round of bad luck's on the house.",
        "Why hello, trouble. The tables have been downright borin' without you.",
        "Speak of the devil and the devil buys in. Welcome, sugar.",
        "You again? My favorite kind of trouble just walked in, darlin'.",
        "Warm up your luck by the fire, hon - then feed it to the tables.",
        "The band's playin', the wheel's turnin', and your seat's open, sugar.",
        "Look alive, everybody - the big spender's arrived! ...I assume.",
        "Evenin', darlin'. Left your worries at the door? Bring the gold, though.",
        "There's a face the felt's been missin'. Sit yourself down, hon.",
        "Welcome in, sugar. Fortune's shufflin' up somethin' special, I feel it.",
        "Well butter my biscuit, look who decided to grace us. Hey there, darlin'.",
        "Come on in where it's warm and the odds are... well, come on in, hon.",
        "Well if it ain't the realm's finest gambler. Or its unluckiest. Come find out, sugar.",
        "The stools are polished and the deck's cut clean. Welcome home, darlin'.",
        "Heard the door creak and hoped it was you, hon. Sit, sit.",
        "Fresh from the road, sugar? Good. Road gold spends best at my tables.",
        "Pull up, pull up. Lady Luck saved you a wink at the door, darlin'.",
        "Another brave soul enters the lion's den. Welcome, hon - mind the lions.",
        "You smell like adventure and desperation, sugar. My two favorite scents.",
        "Evenin', darlin'. Felt's green, drinks are cold, your odds are... festive.",
        "Look who wandered in from the cold, coin purse a-jinglin'. Hey, sugar.",
        "Welcome, high roller. I dusted off your lucky chair myself, hon.",
    ],
    "banter": [
        "Still browsin'? The chips don't stack themselves, darlin'.",
        "Death Roll's quick, if you're feelin' brave. Or foolish. Same thing.",
        "I once saw a gnome win the mega on a two-copper bet. Could be you.",
        "House rule number one: it's only gamblin' if you stop while you're ahead.",
        "That zeppelin in Crash? She always blows. Question is when you jump.",
        "The pots on Azeroth Riches are lookin' real plump tonight, hon.",
        "No rush, sugar. The tables ain't goin' anywhere. Neither's your gold.",
        "You know what they say - scared money don't make money, darlin'.",
        "I'd tell you the odds, but you look like the romantic type.",
        "Take your time. The house has all night, and eventually, all your gold.",
        "Feelin' lucky? 'Course you are. They all do, right up to the end.",
        "A little birdie says the cards are runnin' hot at the poker table.",
        "Between us, sugar, the roulette wheel's got a favorite. Ain't you.",
        "Go on, live a little. You can't take the gold with you, hon.",
        "Every so often somebody walks outta here rich. Ain't seen it, but I hear.",
        "You keep starin' at that board like it's gonna wink back, darlin'.",
        "Cards, dice, or ponies - I don't judge how a body loses their coin.",
        "Word of advice, sugar: the bar's cheaper than the tables. Barely.",
        "My granny always said fortune favors the bold. Granny died broke, but still.",
        "That itch in your palm? That's Lady Luck knockin'. Or a rash. Hard to say.",
        "Slow night for you means a good night for the house, hon. No pressure.",
        "I've watched paladins weep at that felt, darlin'. Come make it three.",
        "You could quit while you're breakin' even... nah, where's the fun in that?",
        "Rumor is the derby's got a long shot runnin' today. Long shots pay, sugar.",
        "Keep your friends close and your gold closer, and both of 'em at my tables.",
        "Bingo's fillin' up. Nothin' like a room full of grown folks yellin' at cards.",
        "You've got the look of somebody about to do somethin' reckless. I approve.",
        "The house never sleeps, darlin', and neither does temptation. Pick a game.",
        "You could stand there thinkin' all night, sugar, or go lose thinkin'.",
        "The wheel doesn't care about your feelin's, darlin'. I do. A little.",
        "Ever notice the exit's real close to the tables? Sit down, hon.",
        "A wise gambler knows when to walk away. Ain't met one yet, sugar.",
        "That poker table's a shark tank with better lightin', darlin'. Dive in.",
        "I've seen fortunes made and lost before the ale went warm, hon.",
        "Superstition's free, sugar. Blow on the dice, kiss the cards, whatever helps.",
        "The house edge is just a suggestion. A very reliable one, darlin'.",
        "Slow and steady loses the gold same as reckless, hon. Pick your speed.",
        "Crash is up, if you like your heart in your throat, sugar.",
        "You've got beginner's eyes tonight, darlin'. The tables love those.",
        "Bet with your head, not over it. Then ignore me and bet big, hon.",
        "The dice have been rattlin' your name all evenin', darlin'. Rude not to answer.",
        "House motto, sugar: come for the gold, stay for the humiliation.",
        "A gnome tried to calculate the odds once. Blew himself up. Just play, hon.",
        "Roulette's a wheel, life's a wheel, everything's a wheel, darlin'. Spin one.",
        "I've buried three pit bosses and outlived two kings. Sit and gamble, sugar.",
        "You hesitatin'? Hesitation's just fear wearin' a fancy hat, hon.",
        "The bar's got dwarven ale that makes even a loss taste sweet, darlin'.",
        "Somebody hit the big one last week and I ain't stopped grinnin', sugar.",
        "High-Lo's the honest man's game. That's why the felt's always empty, hon.",
        "Careful with that lucky feelin', darlin'. That's how the house buys chandeliers.",
        "Coin to be won and pride to be lost - my favorite kind of evenin', sugar.",
        "You could count cards, but the dealer counts kneecaps. Just have fun, hon.",
    ],
    "bye": [
        "Leavin' so soon? The house'll miss ya, sugar.",
        "Cash out while you're smilin'. Come back real soon.",
        "Door's always open, darlin'. Bring friends and fat coin purses.",
        "Off already? Take care now, and don't spend it all in one inn.",
        "G'bye, sugar. The tables'll be warm when you crawl back.",
        "Runnin' off with my winnings, are ya? Cheeky. See you soon.",
        "Safe travels, hon. Try not to lose it all to a pickpocket out there.",
        "Come back anytime, darlin'. The house never closes.",
        "Headin' out? Give Azeroth my regards, sugar.",
        "Bye now. Dream of jackpots and come back hungry, hon.",
        "You're leavin' me? And here I thought we had somethin', darlin'.",
        "Off you go, sweetheart. The felt keeps your seat warm, promise.",
        "Take it easy out there. Trouble's cheaper in here anyway, sugar.",
        "Till next time, high roller. Don't be a stranger and don't get robbed.",
        "Adios, darlin'. Come back when your purse jingles again.",
        "See ya, sugar. I'll keep the good luck on ice for your return.",
        "Quittin' while you're ahead? Now that's just showin' off, sugar.",
        "Mind the step and the pickpockets, darlin'. Come back with friends.",
        "The felt'll keep till mornin', hon. So will your losses. G'night.",
        "Off into the world, sugar. Make it back before your luck does.",
        "Farewell, high roller. The chandeliers dim a little without you.",
        "Go on then, darlin'. But you'll dream of that wheel, mark my words.",
        "Take care out there, hon - it's a rough realm and I'm the safe part.",
        "See you soon, sugar. The house is patient. Terribly, terribly patient.",
        "Leavin' with your boots still on? Impressive, sugar. Come back barefoot.",
        "The night's young and so's your gold, darlin'. But go on, rest up.",
        "Off to spend it or hide it, hon? Come back and we'll relieve you of it.",
        "Safe roads, sugar. The wilds are dangerous - almost as much as my felt.",
        "Bye now, darlin'. I'll leave a candle lit and a bad beat waitin'.",
        "Runnin' already? The wheel's gonna pout, hon. See you soon.",
        "Go count your winnin's in private, sugar. The house wants 'em back Tuesday.",
        "Till we meet again, high roller. Don't let honest work spoil ya, darlin'.",
    ],
    "win": [
        "Ha! Would you look at that - winner winner!",
        "That's how it's done, sugar! The house is impressed.",
        "Ohhh, you lucky thing. Do it again!",
        "Rakin' it in tonight, aren't we, darlin'?",
        "Now that's a hand. Buy yourself somethin' shiny.",
        "Winner! Don't let it go to your head, sugar.",
        "Well slap my garters, you actually won!",
        "Look at all that gold headin' your way, hon.",
        "The house bows to you this round, darlin'.",
        "Beginner's luck? Whatever it is, keep it comin'!",
        "Yeehaw! That's a payout worth cheerin' for.",
        "Somebody's buyin' the next round, and it ain't me!",
        "Sharp play, sugar. Lady Luck's sweet on you tonight.",
        "Ka-ching! Music to my ears, darlin'.",
        "You devil, you cleaned 'em right out!",
        "That's a winner - quit while you're pretty and ahead.",
        "Would you look at that grin. Earned every bit of it, sugar.",
        "The gods of gold are smilin' on you, hon. Smile back!",
        "Winner! I'd be jealous if I weren't so proud, darlin'.",
        "Countin' your winnin's already? Good, more where that came from.",
        "That's the sweet sound of somebody else's luck runnin' out. Nice work.",
        "Oh, you're on a heater now, sugar. Ride it!",
        "The felt loves you tonight, darlin'. Don't tell the others.",
        "Clean sweep! Somewhere a pit boss just got a headache, hon.",
        "Pay the winner! And honey, that's you.",
        "Now THAT'S a hand worth framin'. Well done, sugar.",
        "Lady Luck kissed you right on the mouth that time, darlin'.",
        "Winner winner! The house forgives you. This once.",
        "There it is! Somebody's walkin' taller already, sugar.",
        "The felt just paid its respects, darlin'. Enjoy every coin.",
        "Winner! I'd bottle that luck and sell it if I could, hon.",
        "Clean as a whistle, sugar - straight to your purse it goes.",
        "Look at you readin' the table like a storybook, darlin'. Win!",
        "That's a payout with your name carved right in it, hon.",
        "Yes! The house grumbles and pays. My favorite sound, sugar.",
        "You beautiful, lucky creature - do it again, darlin'!",
        "Gold rains down and it's rainin' on you, hon. Lovely weather.",
        "Winner takes it, sugar! Buy somethin' foolish, you earned it.",
        "The dice bowed, the cards folded, the gold moved - to you, darlin'.",
        "Ha! Sweet victory, hon. Wear it well and bet it soon.",
        "Would you LOOK at that - the felt just handed you a love letter, sugar!",
        "Winner! Somewhere a goblin banker just wept, darlin'. Beautiful.",
        "That's the sweet stuff, hon - gold slidin' your way like it's got places to be.",
        "You cracked it, sugar! The house is gonna need a moment.",
        "Fortune leaned right over and kissed you, darlin'. Don't wash that cheek.",
        "Ka-ching and hallelujah, hon - that's a winner if I ever saw one!",
        "The cards confessed, and they confessed to YOU, sugar. Winner!",
        "Gold in, gold out, gold to you, darlin'. That's how the good nights go.",
        "Ha! You've got the devil's own luck tonight, hon. Keep it wicked.",
        "That's a payday, sugar! Your ancestors are proud and a little confused.",
        "Winner winner - the wheel picked you, and the wheel picks nobody, darlin'.",
        "Slick as a Gadgetzan salesman, hon - you won clean!",
    ],
    "lose": [
        "Oof. The house thanks you for your donation, hon.",
        "Ouch, sugar. Shake it off - luck's a fickle lady.",
        "That one stung. Better luck next hand, darlin'.",
        "And it's gone. Happens to the best of us, sweetheart.",
        "The house wins again. Don't worry, hon, it usually does.",
        "Aw, tough beat, sugar. Dust yourself off.",
        "Empty pockets already? That was quick, darlin'.",
        "Chin up, hon. You can always lose it back another day.",
        "The cards giveth, and honey, tonight they taketh.",
        "That's gamblin', sugar. Sometimes she bites.",
        "Rough one. The house does appreciate the business, though.",
        "Down but not out, right darlin'? ...Right?",
        "Well, that gold had a good run. Brief, but good.",
        "Fortune's a cruel mistress, hon. Try her again.",
        "Oof, right in the coin purse. My condolences, sugar.",
        "The felt taketh what the felt wants, darlin'. Nothin' personal.",
        "That's a loss, hon, but you wore it with such dignity.",
        "Easy come, easy go, sugar. Mostly go, tonight.",
        "Don't cry over spilt gold, darlin'. Cry over the next hand.",
        "The house sends its thanks and a tiny violin, sweetheart.",
        "Swing and a miss, sugar. Happens to sluggers and suckers alike.",
        "Luck stepped out for a smoke, hon. She'll be back. Maybe.",
        "That gold's gone to a better place. My pocket, darlin'.",
        "Ooh, unlucky. Rub the dice, kiss the cards, try again, sugar.",
        "The tables giveth confidence and taketh gold, hon. Balanced, really.",
        "A loss is just a win you haven't had yet, darlin'. Keep tellin' yourself.",
        "Well, that's one way to lighten your load, sugar. Feel free-er?",
        "Tough break, high roller. Even the mighty stumble at my felt.",
        "Well, the felt's got a mean streak tonight, sugar. Try her again.",
        "Gone like mornin' mist, darlin'. That's the game, that's the game.",
        "The house sends flowers and a thank-you note, hon.",
        "Ouch. Somewhere that gold's laughin' at ya, sugar. Get it back.",
        "A donation to the house fund, darlin'. Very generous of you.",
        "Luck took a wrong turn there, hon. She'll be back. Probably.",
        "That one hurt to watch, sugar. Almost. I'm a professional.",
        "Down goes the gold, darlin'. Dust off, chin up, bet on.",
        "The tables taketh, hon. It's practically their whole personality.",
        "Rough hand, sugar. Even Lady Luck naps sometimes.",
        "And it's the house by a nose. Again. Shockin', darlin'.",
        "Money comes, money goes - mostly to me, hon. No hard feelin's?",
        "The felt bared its teeth that time, sugar. It happens. Bet again.",
        "There goes another handful, darlin' - the house does love a generous soul.",
        "Ooh, that gold packed a bag and left, hon. Cold, but that's cards.",
        "A loss, sugar. Write it off as tuition and try the lesson again.",
        "The dice rolled cruel, darlin'. They're moody like that.",
        "Somewhere your gold's buyin' ME a new hat, hon. My condolences.",
        "That one slipped clean through your fingers, sugar. Grip tighter next hand.",
        "Down goes the stack, darlin'. Fortune's got a mean streak tonight.",
        "Ouch, right in the coin purse again, hon. Too generous for your own good.",
        "The house thanks you kindly, sugar - lean week for the chandeliers.",
        "Luck ducked out the back, darlin'. She does that. Bet on, she'll return.",
        "And it's gone. Poof. Like a mage without a reagent, hon.",
    ],
    "bust": [
        "Busted! Too greedy, sugar.",
        "Over twenty-one, hon. Ouch.",
        "Busted! Greedy, greedy. The house loves greedy.",
        "Over twenty-one, sugar. That's a paddlin'.",
        "Bust! One card too many, darlin'.",
        "Poof - you blew right past it, hon.",
        "Twenty-two? Honey, the goal was twenty-one.",
        "Bust! Shoulda quit while you were pretty.",
        "And you're cooked, sugar. The house says thank you.",
        "Over the top! Greed'll getcha every time, darlin'.",
        "Busted flat! That extra card was a trap, hon, and you fell in.",
        "Whoops - sailed right past twenty-one, sugar. Bon voyage.",
        "Too many pips, darlin'. The dealer thanks you kindly.",
        "Bust! You had a good thing and you just HAD to push it, hon.",
        "And that's a bust. One more card than the good Lord allowed, sugar.",
        "Over you go! Should've stood pat, darlin'.",
        "Twenty-three?! Honey, we count DOWN from there, not up.",
        "Cooked, sugar. The house didn't even have to try that time.",
        "Bust! Somewhere a gnome mathematician is shakin' his head.",
        "Ohhh, busted. That's what wantin' too much gets ya, darlin'.",
        "Kaboom, over the line! One card too bold, sugar.",
        "Busted right past the finish, darlin'. Greedy fingers.",
        "And you've gone and cooked it, hon. Twenty-one was RIGHT there.",
        "Too rich for the deck's blood, sugar - bust!",
        "Whoops-a-daisy, over you go, darlin'. The house tips its hat.",
        "That's a bust, hon. The one time less was more, you went more.",
        "Sailed clean past twenty-one, sugar. Wave goodbye to that hand.",
        "Bust! You had it, pushed it, lost it, darlin'. Classic.",
        "Splat, over you sail, sugar - twenty-two's a lonely number.",
        "Busted clean past the mark, darlin'. That extra card was a liar.",
        "And you've cooked the hand, hon - shoulda quit two pips ago.",
        "Over the moon and over twenty-one, sugar. Greedy little thing.",
        "Bust! The deck warned ya and you didn't listen, darlin'.",
        "Too many, hon - the house didn't even break a sweat that time.",
        "You blew right past paradise, sugar. Bust and busted.",
        "That's a bust, darlin' - one card shy of smart, one past lucky.",
    ],
    "blackjack": [
        "Blackjack! Twenty-one on the nose, you gorgeous thing.",
        "Blackjack! Now that's how you do it, sugar.",
        "Ooh, a natural! The house tips its hat, darlin'.",
        "Twenty-one! Somebody's kissed by Lady Luck herself.",
        "Blackjack, sugar! Pay the lady.",
        "A perfect hand! Don't get used to it, hon.",
        "Natural twenty-one! Well aren't you just the cat's pajamas.",
        "Blackjack! The house winces. Beautiful, darlin'.",
        "Ace and a face - blackjack, sugar! Textbook.",
        "Twenty-one right off the deal! Show-off, hon.",
        "Blackjack, darlin'! I'd frame that hand if I could.",
        "Natural! The dealer's cursin' under his breath, sugar.",
        "Ohhh, blackjack! The felt just fell in love with you, hon.",
        "Twenty-one! Clean, pretty, and paid. Nice, darlin'.",
        "Blackjack! Do that again and I'll have to check your sleeves, sugar.",
        "A natural twenty-one! The house pays extra for pretty like that, hon.",
        "Blackjack! The prettiest two cards in the house, sugar.",
        "A natural! Empty sleeve, full luck, darlin'.",
        "Twenty-one on the deal, hon! The dealer just sighed clean out.",
        "Blackjack, sugar - crisp, clean, and paid a premium.",
        "Ohh, a snapper! That's dealer heartbreak right there, darlin'.",
        "Perfect twenty-one, hon! Even the house has to smile.",
        "Blackjack! Frame it, kiss it, cash it, sugar.",
        "A natural beauty, darlin' - twenty-one, not a card wasted.",
        "Blackjack! Two cards, zero mercy for the dealer, sugar.",
        "A natural twenty-one, darlin' - the deck showed up just for you.",
        "Snapper! The dealer's still findin' his jaw on the floor, hon.",
        "Blackjack, sugar! Pretty as a Silvermoon sunrise.",
        "Twenty-one clean off the top, darlin'! Somebody's charmed tonight.",
        "Ohh, a natural, hon - the house pays extra and pouts twice as hard.",
        "Blackjack! You lucky, lovely thing - collect that premium, sugar.",
        "Ace and a picture, darlin' - textbook, gorgeous, paid.",
    ],
    "jackpot": [
        "Jackpot! Ring the bell, we got a winner!",
        "The whole pot, sugar?! Somebody pinch me!",
        "Cha-ching! That's a life-changin' pull right there!",
        "JACKPOT! I ain't never seen the like, darlin'!",
        "The big one! Honey, you just broke the bank!",
        "Sound the alarm - we got ourselves a jackpot winner!",
        "Sweet merciful gold, that's the JACKPOT, sugar!",
        "Winner winner, the whole dang dinner! Jackpot!",
        "JACKPOT! Grab a wheelbarrow, hon, you'll need it!",
        "The machine just surrendered everything, darlin' - jackpot!",
        "Hold onto your hat, sugar, that's a full JACKPOT!",
        "Ka-BLAM! The whole pot's yours, hon! Unbelievable!",
        "Jackpot! I'm gettin' misty over here, darlin'.",
        "Every last coin, sugar - that's the JACKPOT of your dreams!",
        "Ring-a-ding-ding! Jackpot! The house is officially cryin', hon.",
        "The reels lined up and the heavens opened - JACKPOT, darlin'!",
        "JACKPOT! Call the guards, we got a fortune loose in here!",
        "The whole pot's gone home with you, sugar - unheard of!",
        "Bells, whistles, the works - JACKPOT, darlin'! I'm shakin'!",
        "That's generational gold, hon! The JACKPOT smiled on you!",
        "Sweet fancy Moses, a JACKPOT! Pinch me, sugar, I ain't dreamin'!",
        "The machine emptied its whole soul - jackpot, darlin'!",
        "JACKPOT! Your grandkids'll tell stories about this pull, hon.",
        "Every coin, every last one - JACKPOT, sugar! Unbelievable!",
        "JACKPOT! Sound the horns, wake the guards, we got a legend, sugar!",
        "The whole blessed pot, darlin'! I'm gonna need smellin' salts!",
        "Jackpot, hon! That's buy-a-castle money right there!",
        "The reels surrendered EVERYTHING, sugar - JACKPOT!",
        "Sweet gold above, a jackpot, darlin'! The machine's sobbin'!",
        "JACKPOT! Retire on that one, hon - or don't, and see me tomorrow!",
        "Every last coin coughed up at once, sugar - that's a JACKPOT!",
        "Ring the bell twice, darlin' - a real, honest-to-goodness jackpot!",
    ],
    "bigwin": [
        "Big money, big money! Look at you go!",
        "Whoo! The machine's practically beggin' for mercy.",
        "Now that's a payout, darlin'. Don't spend it all in one inn.",
        "The reels are on fire, sugar! Keep 'em spinnin'!",
        "Huge! The pit boss just spat out his drink, hon.",
        "That's a heavy haul, darlin'. Mind your back liftin' it.",
        "Loaded up! The house is sweatin' now, sugar.",
        "Massive win! You're makin' me look bad, hon.",
        "Big ol' payout! The machine owes you an apology and its lunch money.",
        "Whoo-ee, that's a fat one, darlin'! Keep it rollin'.",
        "The reels just coughed up a fortune, sugar. Lucky you!",
        "That's a haul and a half, hon. Somebody's eatin' good tonight.",
        "Big win! The machine's lights are practically weepin', darlin'.",
        "Ka-ching times ten, sugar! Now THAT'S a spin.",
        "Heavy pockets alert! Big winner right here, hon.",
        "The house felt that one, darlin'. Big, beautiful win.",
        "Big ol' haul, sugar! The machine's still catchin' its breath.",
        "Whoo-ee, that's a fat stack, darlin'! Don't strain somethin'.",
        "The reels sang for you, hon - big, beautiful win!",
        "That's a heavyweight payout, sugar. The house is wincin'.",
        "Loaded to the brim, darlin'! Somebody eats like a king tonight.",
        "Big money rollin' in, hon! Keep that machine scared.",
        "A monster win, sugar! The lights are practically applaudin'.",
        "That's a purse-buster, darlin'! Mind your posture haulin' it out.",
        "Big haul incomin', sugar - the machine's runnin' low on dignity!",
        "Whoo, that's a heavyweight, darlin'! Somebody bring a cart.",
        "The reels went and paid a fortune, hon - big, bold, beautiful!",
        "That's a fat payout, sugar. The pit boss just aged a year.",
        "Loaded up sky-high, darlin'! Eat well tonight, you earned it.",
        "Big money rollin' your way, hon - keep that machine humble.",
        "A whopper of a win, sugar! The lights are downright giddy.",
        "That's a back-breaker of a payout, darlin' - lift with your knees!",
    ],
    "debt": [
        "Payin' up like a gentleman. The house respects that.",
        "There she goes - square with the world again, sugar.",
        "Good on ya for settlin'. Beats hidin' in Booty Bay.",
        "Debts paid, conscience clean. Almost, darlin'.",
        "Look at you, honorin' your markers. Rare quality, hon.",
        "Tab's cleared, sugar. You're welcome back anytime.",
        "Nice and square. No goons comin' for ya tonight, darlin'.",
        "Paid in full. The house does love a reliable loser.",
        "Settlin' up already? A body could get used to you, sugar.",
        "There's an honest gambler, darlin'. They put you in the museum.",
        "Marker cleared! Sleep easy tonight, hon.",
        "Payin' what you owe - I'd kiss you if it weren't unprofessional, sugar.",
        "Square and clean. That's how legends keep their kneecaps, darlin'.",
        "Debt handled like a champ. The house salutes you, hon.",
        "All settled up, sugar. Now go make some fresh mistakes.",
        "Good as gold and twice as honest. Tab's clear, darlin'.",
        "Squared up like a saint, sugar. The house is almost touched.",
        "Payin' your markers on time - who raised you right, darlin'?",
        "Tab wiped clean, hon. Sleep like a baby tonight.",
        "There's honor for ya, sugar - debt paid, no drama.",
        "All settled, darlin'. The bruisers can stay home tonight.",
        "Good as your word and twice as prompt, hon. Rare, that.",
        "Cleared the slate, sugar. Now go dirty it up again.",
        "Debt handled with grace, darlin'. The house doffs its cap.",
        "Paid up prompt as sunrise, sugar. The house is downright misty.",
        "Settlin' clean - somebody's momma raised 'em right, darlin'.",
        "Tab's gone, conscience clear, kneecaps safe, hon. Well played.",
        "Square as an Ironforge brick, sugar. The house salutes ya.",
        "Debt cleared without a fuss, darlin'. Rare as a polite murloc.",
        "Paid in full and on time, hon - a credit to gamblers everywhere.",
        "There's a gambler who honors the game, sugar. Slate's wiped clean.",
        "All squared up, darlin'. Go on and make some fresh trouble.",
    ],
    "paid": [
        "Cha-ching! Money in your pocket, darlin'.",
        "Somebody just made good on their tab. Sweet, sweet gold.",
        "Collectin' what you're owed - I like your style, sugar.",
        "Gold incomin', hon! Told you they were good for it.",
        "Paid at last! Don't let 'em run a tab that long again, darlin'.",
        "Ding! Your debt just got settled, sugar. Count it.",
        "There it is - coin in hand, hon. Justice tastes like gold.",
        "Somebody paid up! Bank it before they change their mind, darlin'.",
        "Your marker just came home, sugar. Welcome back, little coins.",
        "Debt collected, no arm-twistin' required. Civilized, hon!",
        "Gold's in the purse, darlin'. Feels good, don't it?",
        "Paid in full and no goons involved - a rare treat, sugar.",
        "Cash money, hon! That's what bein' owed feels like.",
        "There you go, sugar - the debt fairy came through.",
        "Ka-ching, your coin came callin', sugar! Bank it quick.",
        "Somebody paid their dues, darlin' - gold in your grip.",
        "Owed and delivered, hon! That's the good kind of surprise.",
        "Your winnings walked right home, sugar. Count 'em twice.",
        "Debt made good, darlin'! No arm-twistin', just gold.",
        "There it is - paid in full, hon. Feels righteous, don't it?",
        "Ding ding, your coin came marchin' home, sugar!",
        "Somebody made good, darlin' - fresh gold in the purse.",
        "Owed and paid, hon! Best surprise since the free ale ran out.",
        "There it comes, sugar - your winnin's, right on schedule.",
        "Debt collected, no goons required, darlin'. Civilized!",
        "Gold in hand, hon - that's the good kind of jingle.",
    ],
    # per-game "table just opened" announcements
    "open_blackjack": [
        "Blackjack's open, sugar! Grab a seat and try your luck.",
        "Fresh blackjack table! Come see if you can beat the dealer.",
        "Twenty-one's callin', hon - blackjack's live!",
        "Blackjack table's up! Hit, stand, or chicken out - your call.",
        "Cards are out for blackjack, darlin'. Ante up!",
        "Blackjack's dealin', sugar! Come chase that twenty-one.",
        "Somebody opened blackjack, hon - the dealer's waitin' on you.",
        "New blackjack game! Beat seventeen and keep your nerve, darlin'.",
        "Blackjack's live, sugar! Doubles, splits, and bad decisions welcome.",
        "The blackjack felt's warm, hon. Come sit before the seats fill.",
        "Twenty-one, anyone? Blackjack's open and the shoe is fresh, darlin'.",
        "Blackjack table's callin' your name, sugar. Don't keep it waitin'.",
        "Blackjack's dealin', sugar! Come tempt that twenty-one.",
        "Fresh shoe, fresh blackjack table, darlin' - seats are goin'!",
        "Somebody wants blackjack, hon! Beat the dealer or bust tryin'.",
        "Blackjack's live, sugar - hit me, or don't, but come play!",
        "New blackjack game, darlin'! The dealer's feelin' beatable.",
        "Cards up for blackjack, hon! Ante in before the shoe cools.",
        "Blackjack's open, sugar - come dance with the dealer!",
        "Fresh twenty-one table, darlin'! Seats fillin', shoe's crisp.",
        "Blackjack's callin', hon - hit hard or stand proud!",
        "Somebody's dealin' blackjack, sugar. Beat seventeen and grin.",
        "New blackjack game up, darlin' - the dealer looks nervous.",
        "Cards are flyin' for blackjack, hon - ante in!",
    ],
    "open_poker": [
        "Five Card Stud's open, sugar! Bring your poker face.",
        "Stud poker's live, hon - time to bluff somebody broke.",
        "Fresh Five Card Stud table! Read 'em and weep, darlin'.",
        "Poker's on! Stud rules - come test your nerve.",
        "Five Card Stud's dealin', sugar. Get in while the seats last.",
        "Stud poker's open, hon! Keep your tells to yourself.",
        "New Five Card Stud game, darlin' - ante up and lie well.",
        "Poker table's live, sugar. Bring gold and a straight face.",
        "Five Card Stud's callin'! Who's got the nerve, hon?",
        "Stud's dealin', darlin'. Best hand or best bluff takes it.",
        "Fresh poker felt, sugar! Come separate a friend from their coin.",
        "Five Card Stud's open! Cards up, hearts steady, hon.",
        "Five Card Stud's dealin', sugar - poker faces on!",
        "Fresh stud game, darlin'! Bluff a friend outta house and home.",
        "Poker's live, hon! Best hand or best liar wins - your pick.",
        "Somebody opened Five Card Stud, sugar. Sharpen that stare.",
        "Stud poker's callin', darlin'! Gold on the felt, secrets in your eyes.",
        "New poker table, hon - come see who cracks first.",
        "Five Card Stud's open, sugar - poker faces to the ready!",
        "Fresh stud table, darlin'! Come lie your way to a fortune.",
        "Poker's callin', hon - bluff bold or fold fast!",
        "Somebody wants Five Card Stud, sugar. Bring nerve and gold.",
        "Stud's dealin', darlin' - secrets in, chips out.",
        "New poker game up, hon - who blinks first?",
    ],
    "open_holdem": [
        "Texas Hold'em's open, darlin'! Flop, turn, and river await.",
        "Hold'em table's live, sugar - two cards and a dream.",
        "Fresh Hold'em game! Come shove your chips in, hon.",
        "Texas Hold'em's dealin'! Blinds are up, darlin'.",
        "Hold'em's on the felt, sugar. All in or all out?",
        "Somebody opened Hold'em, hon - grab your two hole cards!",
        "Texas Hold'em's live, darlin'! Play the board, play your nerve.",
        "New Hold'em game, sugar. Small blind's watchin' you.",
        "Hold'em's dealin', hon! Come see the flop and lose your senses.",
        "Fresh Texas Hold'em, darlin' - big pots, bigger bluffs.",
        "Hold'em table's open, sugar! Suited connectors, don't fail me now.",
        "The community cards are itchin' to flop - Hold'em's live, hon!",
        "Hold'em's dealin', sugar! Two cards, five to come, nerves of steel.",
        "Fresh Texas Hold'em, darlin' - the flop's itchin' to fall!",
        "Hold'em's live, hon! Play the board, bluff the rest.",
        "Somebody opened Hold'em, sugar. The blinds are hungry.",
        "Texas Hold'em's callin', darlin'! Come shove it all in.",
        "New Hold'em game, hon - the river's waitin' to break some hearts.",
        "Hold'em's open, sugar - two cards and a whole lotta hope!",
        "Fresh Texas Hold'em, darlin'! The flop's loaded and waitin'.",
        "Hold'em's callin', hon - shove it in or slink away!",
        "Somebody dealt Hold'em, sugar. Mind those blinds.",
        "Texas Hold'em's live, darlin' - the river's feelin' cruel.",
        "New Hold'em table, hon - come chase the nuts!",
    ],
    "open_hilo": [
        "High-Lo's open, hon! Higher or lower - easy money. Ha!",
        "Fresh High-Lo table, sugar. Call it right and cash in.",
        "High-Lo's live! Trust your gut, darlin'.",
        "Guess high, guess low - High-Lo's open, sugar!",
        "High-Lo's rollin', hon. Come take a punt.",
        "New High-Lo game, darlin'! Fifty-fifty and a prayer.",
        "High-Lo's callin', sugar - highest roll rakes it in.",
        "Somebody opened High-Lo, hon. Feelin' lucky with a number?",
        "High-Lo's live, darlin'! Simple as up or down.",
        "Fresh High-Lo, sugar! Roll big or go home lighter.",
        "High-Lo's dealin' the dice, hon - come test that gut of yours.",
        "High or low, darlin'? The High-Lo table wants your guess.",
        "High-Lo's dealin', sugar! Trust your gut and guess.",
        "Fresh High-Lo, darlin' - one number between you and gold.",
        "High-Lo's live, hon! Higher, lower, richer, poorer.",
        "Somebody opened High-Lo, sugar. Feelin' a lucky roll?",
        "High-Lo's callin', darlin'! Simplest game, cruelest odds.",
        "New High-Lo table, hon - come chance your number.",
        "High-Lo's open, sugar - one guess between poor and pleased!",
        "Fresh High-Lo, darlin'! Trust the gut you were born with.",
        "High-Lo's callin', hon - up, down, or broke!",
        "Somebody wants High-Lo, sugar. Feelin' a big number?",
        "High-Lo's live, darlin' - simplest game, meanest luck.",
        "New High-Lo roll, hon - come chance it!",
    ],
    "open_deathroll": [
        "Death Roll's open, sugar! Roll brave or roll home.",
        "Fresh Death Roll - last one standin' takes it all, darlin'.",
        "Death Roll's live, hon! Pray you don't roll a one.",
        "Somebody wants to Death Roll! Nerves of steel required, sugar.",
        "Death Roll's on! Quick, brutal, and beautiful, darlin'.",
        "New Death Roll game, hon - halve it 'til somebody dies.",
        "Death Roll's callin', sugar! One's the reaper, mind the one.",
        "Fresh Death Roll, darlin'. Two go in, one walks out richer.",
        "Death Roll's live! Feelin' brave or feelin' broke, hon?",
        "Somebody opened Death Roll, sugar - down and down she goes.",
        "Death Roll's on the table, darlin'! Roll and hold your breath.",
        "Fresh duel of dice - Death Roll's open, hon! Who's got the nerve?",
        "Death Roll's dealin', sugar - mind the one, always the one.",
        "Fresh Death Roll, darlin'! Halve it down 'til somebody drops.",
        "Death Roll's live, hon! Two enter, one leaves richer.",
        "Somebody wants Death Roll, sugar. Steel yourself.",
        "Death Roll's callin', darlin' - quick, brutal, glorious.",
        "New Death Roll duel, hon! Roll brave and pray.",
        "Death Roll's open, sugar - and the one is always watchin'!",
        "Fresh Death Roll, darlin'! Halve it down to the bitter end.",
        "Death Roll's callin', hon - two go in, one comes out grinnin'.",
        "Somebody dares a Death Roll, sugar. Steel your nerve.",
        "Death Roll's live, darlin' - quick as a blade, twice as cruel.",
        "New Death Roll duel, hon - roll and hold your breath!",
    ],
    "open_liarsdice": [
        "Liar's Dice is open, sugar! Lie like your gold depends on it.",
        "Fresh Liar's Dice - bluff 'em blind, darlin'.",
        "Liar's Dice is live, hon! Trust no one, least of all me.",
        "Somebody called for Liar's Dice! Sharpen those fibs, sugar.",
        "Liar's Dice on the table, darlin'. Cups up!",
        "Liar's Dice is open, hon! Best liar at the table wins.",
        "Fresh Liar's Dice game, sugar - keep your dice and your lies close.",
        "Liar's Dice is dealin', darlin'! Bid bold, bluff bolder.",
        "New Liar's Dice, hon! Everybody's honest 'til the cups come up.",
        "Liar's Dice is live, sugar - who's fibbin' and who's foldin'?",
        "Cups are rattlin' - Liar's Dice is open, darlin'!",
        "Somebody opened Liar's Dice, hon. Lie sweet, lie often.",
        "Liar's Dice is dealin', sugar - lie sweet, bid bold.",
        "Fresh Liar's Dice, darlin'! Nobody's honest under a cup.",
        "Liar's Dice is live, hon! Read the room, then fib to it.",
        "Somebody opened Liar's Dice, sugar. Trust no one.",
        "Liar's Dice is callin', darlin' - bluff 'em till they crack.",
        "New Liar's Dice game, hon! Cups down, lies up.",
        "Liar's Dice is open, sugar - honesty need not apply!",
        "Fresh Liar's Dice, darlin'! Bluff 'em blind, bid 'em bold.",
        "Liar's Dice callin', hon - read the room, then fib to it!",
        "Somebody opened Liar's Dice, sugar. Cups down, lies up.",
        "Liar's Dice is live, darlin' - trust no one, least of all me.",
        "New Liar's Dice game, hon - sharpen those tall tales!",
    ],
    "open_bingo": [
        "Bingo's open, sugar! Daub 'em quick and holler loud.",
        "Fresh Bingo card's ready, hon - eyes on the numbers!",
        "Bingo's live, darlin'! Somebody's about to yell real happy.",
        "Bingo game's startin', sugar. Grab a card!",
        "Bingo's callin', hon - first to a line wins!",
        "New Bingo round, darlin'! Sharpen your daubers.",
        "Bingo's open, sugar - listen close and mark 'em fast.",
        "Somebody started Bingo, hon! Cards out, ears open.",
        "Fresh Bingo game, darlin'! Nothin' like a lucky card.",
        "Bingo's live, sugar! First to holler takes the pot.",
        "The numbers are rollin' - Bingo's open, hon!",
        "Bingo's dealin' cards, darlin'. Come find your lucky line.",
        "Bingo's dealin' cards, sugar - ears open, dauber ready!",
        "Fresh Bingo round, darlin'! Somebody's about to holler.",
        "Bingo's live, hon! Mark 'em quick, yell 'em loud.",
        "Somebody started Bingo, sugar - grab a lucky card!",
        "Bingo's callin', darlin' - first line takes the pot.",
        "New Bingo game, hon! Nothin' beats a lucky card.",
        "Bingo's open, sugar - eyes sharp, dauber ready!",
        "Fresh Bingo card, darlin'! Somebody's about to yell the roof off.",
        "Bingo's callin', hon - mark 'em quick, holler quicker!",
        "Somebody started Bingo, sugar - grab a lucky card!",
        "Bingo's live, darlin' - first line rakes the pot.",
        "New Bingo round, hon - luck's in the numbers tonight!",
    ],
    "open_roulette": [
        "Roulette's open, sugar! Place your bets, round she goes.",
        "Fresh roulette wheel spinnin', darlin' - red or black?",
        "Roulette's live, hon! Pick a number and hold your breath.",
        "The wheel's turnin' - roulette's open, sugar!",
        "Roulette table's up! No more bets soon, darlin'.",
        "Roulette's callin', hon - lucky number or bust?",
        "Somebody opened roulette, sugar! Where she stops, who knows.",
        "Fresh roulette game, darlin'! Red, black, or feelin' brave?",
        "Roulette's live, hon! The little ball loves nobody.",
        "Spin's about to start - roulette's open, sugar!",
        "New roulette wheel, darlin'! Put your gold on a hunch.",
        "Roulette's dealin' fate, hon - place 'em while you can.",
        "Roulette's dealin' fate, sugar - place 'em quick!",
        "Fresh roulette wheel, darlin'! Red, black, or reckless?",
        "Roulette's live, hon! Pick your number, hold your breath.",
        "Somebody opened roulette, sugar. The little ball's hungry.",
        "Roulette's callin', darlin' - the spin's about to fly!",
        "New roulette game, hon! Bet a hunch, win a fortune.",
        "Roulette's open, sugar - the little ball's hungry for a hunch!",
        "Fresh wheel spinnin', darlin'! Red, black, or a wild guess?",
        "Roulette's callin', hon - pick your number, say a prayer!",
        "Somebody opened roulette, sugar. No more bets comin' soon.",
        "Roulette's live, darlin' - round and round the fortune goes.",
        "New roulette game, hon - bet a whim, win a mountain!",
    ],
    "open_crash": [
        "Crash is open, sugar! Ride the zeppelin, just not too long.",
        "Fresh Crash flight boardin', darlin' - jump before she blows!",
        "Crash is live, hon! How brave you feelin' today?",
        "The zeppelin's leavin' - Crash is open, sugar! Ante up!",
        "Crash game's on, darlin'! Nerve of steel, exit on time.",
        "Crash is boardin', hon! Climb aboard and mind the boom.",
        "Somebody opened Crash, sugar - she always blows, you know when.",
        "Fresh Crash flight, darlin'! Greed gets you higher and deader.",
        "Crash is live, hon! Jump early, jump often, jump SOMETHING.",
        "The zeppelin's firin' up - Crash is open, sugar!",
        "New Crash round, darlin'! Ride high, land rich... or don't land.",
        "All aboard the Crash zeppelin, hon! Last one off wins or burns.",
        "Crash is boardin', sugar - climb on, jump smart!",
        "Fresh Crash flight, darlin'! She always blows; you pick when.",
        "Crash is live, hon! Ride high, land rich, or don't land.",
        "Somebody opened Crash, sugar. Nerve of steel required.",
        "Crash's zeppelin's firin' up, darlin' - all aboard!",
        "New Crash round, hon! Greed climbs, wisdom jumps.",
        "Crash is open, sugar - climb aboard, jump before the boom!",
        "Fresh Crash flight, darlin'! She soars, she blows, you choose when.",
        "Crash is callin', hon - ride high, land rich, or don't land!",
        "Somebody boarded Crash, sugar. Nerve of steel, exit on time.",
        "Crash's zeppelin's revvin', darlin' - all aboard the chaos!",
        "New Crash round, hon - greed lifts ya, wisdom drops ya!",
    ],
    # game-specific dramatic moments
    "deathroll_bust": [
        "A one?! Oh sugar, that's the end of the line for you.",
        "Rolled a one, darlin'. Say your prayers, you're done.",
        "Ohhh, snake eye of doom! You're cooked, hon.",
        "A ONE! The dice gods are cruel tonight, sugar.",
        "Down you go, darlin' - a one and it's all over.",
        "And that's a one. Pour one out for your gold, hon.",
        "A one! The reaper called your number, sugar. Pay up.",
        "Ohh, rolled the deadly one, darlin'. It was a good run.",
        "One! That's all she wrote, hon. The dice have spoken.",
        "The dreaded one, sugar! Somewhere a coffin just got smaller.",
        "A ONE, darlin'?! The whole table just gasped. You're done.",
        "Snake eye! The dice turned on you, hon. Brutal.",
        "Rolled a one and rolled right out, sugar. Tough dice.",
        "That's a one, darlin' - the loser's number. Better luck, brave soul.",
        "A one! Oh honey, the reaper just called your name.",
        "Rolled the deadly one, sugar - that's all she wrote.",
        "One! The dice turned traitor on ya, darlin'. Pay up.",
        "Ohh, the fatal one, hon. Somewhere a coffin creaks.",
        "That's a one, sugar - the loser's number, cold and cruel.",
        "Down to a one, darlin'! The table gasps, you groan.",
        "A one! Oh sugar, the reaper's got your ticket now.",
        "Rolled the killer one, darlin' - pack it in, it's over.",
        "One! The dice sold you out cold, hon. Pay the piper.",
        "The dreaded one, sugar - somewhere a gravestone sighs.",
        "Down to a one, darlin' - the loser's number, harsh and true.",
        "That's a one, hon! The whole table winced for ya.",
    ],
    "crash_bail": [
        "You jumped in time, sugar! Smart cookie.",
        "Out clean before the boom - well done, darlin'!",
        "Ha! Bailed with the pot, you sly thing.",
        "Nerves held and you cashed out, hon. Beautiful.",
        "Off the zeppelin and into the gold, sugar!",
        "Perfect exit, darlin'! She blew and you were long gone.",
        "Jumped and landed rich, hon! That's how it's done.",
        "You bailed like a pro, sugar - gold in hand, feet on ground.",
        "Out with the pot and not a singed hair, darlin'. Gorgeous.",
        "Cashed out cool as you please, hon. The house is annoyed.",
        "Chute deployed, pockets full - textbook bail, sugar!",
        "You read that zeppelin like a book, darlin'. Off in the nick of time.",
        "Bailed at the perfect breath, hon! Somebody's been practicin'.",
        "Clean jump, fat pot, no boom on you, sugar. Well played.",
        "Jumped clean, sugar - gold in hand, feet on the ground!",
        "Perfect bail, darlin'! She blew and you were long gone.",
        "Out with the pot, hon! Nerves of pure steel.",
        "You read her right and bailed, sugar - beautifully done.",
        "Chute open, pockets full, darlin' - textbook exit!",
        "Off the zeppelin just in time, hon! The house is sulkin'.",
        "Bailed clean, sugar - pockets fat, boots dry!",
        "Perfect exit, darlin' - she blew and you were already countin' gold.",
        "Out with the pot, hon - ice-cold nerve, that.",
        "You jumped at the sweet spot, sugar - gorgeous timing!",
        "Chute open, gold secure, darlin' - the house is grumblin'.",
        "Off the zeppelin just in time, hon - well read, well done!",
    ],
    "crash_boom": [
        "Boom! You rode her right into the ground, sugar.",
        "Too greedy, darlin' - up in flames you go!",
        "KABOOM! Shoulda jumped, hon.",
        "And she blows, with you still aboard. Oof, sugar.",
        "One more meter and... nope. Splat, darlin'.",
        "The zeppelin wins again! Down in flames, hon.",
        "Boom goes the airship - and your gold with it, sugar.",
        "You held on a breath too long, darlin'. Kaboom.",
        "Up in smoke, hon! Greed rode that zeppelin straight down.",
        "And... she's gone. You with her, sugar. Ouch.",
        "Too high, too long, too greedy - boom, darlin'.",
        "The old girl blew and you were still waverin'. Cooked, hon.",
        "Splat! That's what one more second gets ya, sugar.",
        "Down in a fireball, darlin'. The house waves goodbye to your ante.",
        "Boom! One breath too greedy, sugar - down you go.",
        "Kaboom, darlin'! Shoulda jumped when your gut said jump.",
        "Up in flames, hon - the zeppelin claims another dreamer.",
        "Splat! That's what one more tick buys ya, sugar.",
        "She blew with you aboard, darlin'. Oof. The house waves bye.",
        "Down in a fireball, hon! Greed rode her straight into the dirt.",
        "Boom! One tick too bold, sugar - down in flames.",
        "Kaboom, darlin' - your gut said jump and you argued.",
        "Up in smoke, hon - the zeppelin ate another dreamer.",
        "Splat! That's the price of one more second, sugar.",
        "She blew with you aboard, darlin' - oof, the house waves.",
        "Down in a blaze, hon - greed flew her right into the dirt.",
    ],
    # Death Roll: someone rolled dangerously low (close call)
    "deathroll_close": [
        "Ooooh, that's a low one! Somebody's sweatin' now.",
        "Yikes, cuttin' it close, sugar. One foot in the grave.",
        "That roll was a whisper from doom, darlin'.",
        "Mercy! A hair from the reaper on that one, hon.",
        "Close call! The dice are feelin' spicy tonight.",
        "Oof, right to the edge, sugar. Don't blink.",
        "That's dangerously low, darlin'. Palms gettin' clammy?",
        "Ooh, the reaper's tappin' a shoulder now, hon.",
        "Low roll! That's a knuckle-whitener, sugar.",
        "Teeterin' on the edge, darlin'. One bad roll from the end.",
        "That number's low enough to spook a ghost, hon.",
        "Yeesh, cuttin' it fine! The whole table leaned in, sugar.",
        "Ooh, a nail-biter of a roll, sugar - one foot in the grave.",
        "Dangerously low, darlin'! The whole table just leaned in.",
        "Yikes, a hair from doom, hon. Palms sweatin' yet?",
        "That roll's low enough to spook the reaper himself, sugar.",
        "Cuttin' it fine, darlin'! One bad number from the end.",
        "Whew, right on the edge, hon - don't you dare blink.",
        "Ooh, that roll's a whisker from doom, sugar - sweaty palms yet?",
        "Dangerously low, darlin' - the whole room leaned in!",
        "Yikes, right at death's door, hon - don't you blink.",
        "That number's low enough to spook a banshee, sugar.",
        "Cuttin' it razor-thin, darlin' - one bad roll from the grave.",
        "Whew, teeterin' on the edge, hon - nerve of steel now.",
    ],
    # Roulette: bets are locked, wheel spins
    "roulette_nobets": [
        "No more bets, darlin'! Round and round she goes.",
        "That's it - no more bets! Hold your breath, sugar.",
        "Bets are locked, hon. Where she stops, nobody knows.",
        "No more bets! The little ball's got your fate now.",
        "Wheel's spinnin', sugar - it's outta your hands.",
        "Hands off the table! Let's see where she lands, darlin'.",
        "No more bets, hon! Now we pray to the little ball.",
        "Locked and spinnin', sugar - too late to second-guess.",
        "That's all the bets, darlin'! Round she goes, tick tick tick.",
        "Bets closed! Now it's just you and the wheel, hon.",
        "No more wagers, sugar - fate's in motion.",
        "Off with the hands, darlin'! The wheel decides now.",
        "No more bets, sugar - round and round the fate goes!",
        "Bets are locked, darlin'! Now we beg the little ball.",
        "That's it, hands off, hon - the wheel decides now.",
        "No more wagers, sugar! Hold your breath and your hope.",
        "Locked and spinnin', darlin' - too late for second thoughts.",
        "Off the table, everyone - she's spinnin', hon!",
        "No more bets, sugar - the wheel owns your fate now!",
        "Bets locked, darlin' - now we plead with the little ball.",
        "Hands off, hon - she's spinnin' and she's deaf to prayers.",
        "No more wagers, sugar! Hold your breath and your hope.",
        "Locked and rollin', darlin' - too late to change your mind.",
        "Off the felt, everyone - round she goes, hon!",
    ],
    # Bingo: you got it
    "bingo_win": [
        "BINGO, sugar! Holler it loud and proud!",
        "BINGO! Look at you, quick eyes and all.",
        "That's a BINGO, darlin'! Card's a winner!",
        "BING-O! The whole hall heard that one, hon.",
        "Winner winner - BINGO, sugar! Rake it in.",
        "BINGO! Somebody's daubin' fast tonight, darlin'.",
        "BINGO, hon! Sharpest eyes in the house.",
        "That's the magic word - BINGO, sugar! Collect your pot.",
        "BINGO! The room's gonna be jealous, darlin'.",
        "A winnin' card! BINGO, hon - beautifully daubed.",
        "BINGO! Lucky numbers found their home, sugar.",
        "There it is - BINGO, darlin'! First and best.",
        "BINGO, sugar! The whole hall heard that holler!",
        "That's a winnin' card - BINGO, darlin'! Rake it in.",
        "BING-O, hon! Sharpest eyes and quickest dauber in the room.",
        "BINGO! Lucky numbers came home, sugar. Collect that pot.",
        "There it is, BINGO, darlin'! First and finest.",
        "A full card, BINGO, hon! Beautifully daubed, you.",
        "BINGO, sugar - the whole hall jumped at that one!",
        "Winnin' card - BINGO, darlin'! Scoop that pot up.",
        "BING-O, hon - fastest dauber in the west!",
        "BINGO! Lucky numbers came marchin' home, sugar.",
        "There it is, BINGO, darlin' - first, best, and loud!",
        "A full card, BINGO, hon - beautifully done, you!",
    ],
    # Liar's Dice: a challenge resolved and it wasn't your die
    "liarsdice_challenge": [
        "LIAR! Ooh, somebody got called out, sugar.",
        "The dice don't lie, but the players sure do, darlin'!",
        "Called a liar! This is my favorite part, hon.",
        "Somebody's bluff just got sniffed out, sugar.",
        "Cups up! The truth comes out, darlin'.",
        "Ha! A challenge! Let's see who was fibbin', hon.",
        "The gauntlet's down - challenge! Cups up, sugar!",
        "Somebody smelled a lie, darlin'. Reveal 'em!",
        "Called out! The table holds its breath, hon.",
        "A challenge! Now we see who's honest and who's toast, sugar.",
        "Ooh, the bluff got questioned, darlin'! Cups to the sky.",
        "Somebody said 'liar' - and now we find out, hon!",
        "LIAR! Somebody's bluff just got sniffed out, sugar.",
        "Challenge! Cups to the sky, darlin' - truth time.",
        "Somebody called it, hon! Let's see who was fibbin'.",
        "The gauntlet's down, sugar - reveal those dice!",
        "Ooh, a challenge, darlin'! My favorite kind of drama.",
        "Somebody yelled liar, hon - now we find the truth.",
        "LIAR! Somebody's fib just hit the fan, sugar.",
        "Challenge! Cups to the ceiling, darlin' - truth time!",
        "Somebody called the bluff, hon - let's see the dice!",
        "Gauntlet's thrown, sugar - reveal 'em all!",
        "Ooh, a challenge, darlin' - my very favorite drama!",
        "Somebody hollered liar, hon - now the truth spills.",
    ],
    # Liar's Dice: YOU lost the challenge (caught or bad call)
    "liarsdice_bluff": [
        "Caught red-handed, sugar! Lose a die.",
        "Your bluff just crumbled, darlin'. Ouch.",
        "Busted lie, hon - there goes a die.",
        "Should've folded that fib, sugar. Down one.",
        "The dice sold you out, darlin'. Tough break.",
        "Called out! Even I believed ya, hon.",
        "Your fib fell apart, sugar - hand over a die.",
        "The cups came up and the lie came down, darlin'. Minus one.",
        "Caught bluffin', hon! Even a con artist has bad nights.",
        "Down a die, sugar. That story had holes.",
        "The table saw through you, darlin'. Losin' a die stings, don't it?",
        "Oof, your bluff got called and busted, hon. One die lighter.",
        "Caught fibbin', sugar - hand over a die.",
        "Your lie fell flat, darlin'. Down a die you go.",
        "Busted bluff, hon! Even I nearly believed that one.",
        "The cups told on ya, sugar - minus one die.",
        "That story had holes, darlin'. Losin' a die stings, don't it?",
        "Called and cooked, hon - your bluff's in pieces.",
        "Caught fibbin' red-handed, sugar - hand over a die.",
        "Your tall tale toppled, darlin' - down a die you go.",
        "Busted bluff, hon - and I nearly bought it, too.",
        "The cups ratted on ya, sugar - minus one.",
        "That lie had holes you could sail through, darlin'. Lose a die.",
        "Called and cooked, hon - your bluff's in tatters.",
    ],
    # table flow: it's your turn
    "turn_nudge": [
        "Your move, sugar. Don't keep the table waitin'.",
        "You're up, darlin'! Whatcha gonna do?",
        "All eyes on you, hon. Make it count.",
        "Your turn, sugar. No pressure... well, a little.",
        "Go on, darlin', the table's waitin' on you.",
        "It's your play, hon. Fortune favors the bold.",
        "Tick tock, sugar - the table's lookin' at you.",
        "Your call, darlin'. Bold or careful, but pick somethin'.",
        "You're on the clock, hon. What's it gonna be?",
        "Whatcha got, sugar? The table's holdin' its breath.",
        "Don't leave 'em hangin', darlin' - your move.",
        "Spotlight's on you, hon. Dazzle us or fold us.",
        "You're up, sugar - the table's tappin' its foot.",
        "Your move, darlin'! Bold or careful, just pick.",
        "All eyes on you, hon. Don't leave 'em waitin'.",
        "Tick tock, sugar - what's it gonna be?",
        "Your play, darlin'! Fortune loves the decisive.",
        "Spotlight's yours, hon - make it a good one.",
        "You're up, sugar - the felt's holdin' its breath.",
        "Your move, darlin' - dazzle us or fold us!",
        "All eyes your way, hon - make it a good one.",
        "Tick tock, sugar - the table's waitin' on ya.",
        "Your call, darlin' - fortune loves a fast hand.",
        "Spotlight's yours, hon - don't keep it waitin'.",
    ],
    # Blackjack: the dealer busted and you won
    "bj_dealerbust": [
        "Dealer busts! Pay the players, sugar - that's you!",
        "Ha! The house went and busted. Lucky you, darlin'.",
        "Dealer's over! Rare treat, hon - collect your winnings.",
        "Bust for the dealer! The tables have turned, sugar.",
        "The house overcooked it! You win, darlin'.",
        "Dealer busted flat - and you're sittin' pretty, hon.",
        "The dealer went and blew it, sugar! Your gold now.",
        "House bust! Don't you love it when they do the losin', darlin'?",
        "Dealer's cooked, hon - stand there and get paid.",
        "Ha! The house busted itself right into your pocket, sugar.",
        "Dealer over twenty-one! Free money, darlin', enjoy it.",
        "The house choked! You win without liftin' a finger, hon.",
        "Dealer busts, sugar - free gold, don't mind if you do!",
        "The house overcooked it, darlin'! You win sittin' still.",
        "Dealer's over twenty-one, hon - the tables turned your way!",
        "House bust! Rare as hen's teeth, sugar - enjoy it.",
        "The dealer choked, darlin'! Collect without liftin' a finger.",
        "Dealer busted flat, hon - and you're sittin' pretty.",
        "Dealer busts, sugar - free gold, don't be shy!",
        "The house overcooked it, darlin' - you win by sittin' still!",
        "Dealer's over the top, hon - the tables turned your way!",
        "House bust, sugar - rare as a generous goblin, enjoy it!",
        "The dealer choked, darlin' - collect without liftin' a finger!",
        "Dealer busted flat, hon - and you're sittin' pretty as ever.",
    ],
    # Blackjack: a push (tie with the dealer)
    "bj_push": [
        "A push, sugar. Nobody wins, nobody cries.",
        "Tie with the house, darlin'. Keep your gold.",
        "Push! You live to bet another hand, hon.",
        "Dead heat, sugar. The house shrugs, you shrug.",
        "A wash, darlin'. Not a loss, not a win.",
        "Even steven, hon. Onto the next.",
        "Push, sugar - the felt calls it a draw.",
        "Tied the dealer, darlin'. Your gold stays put.",
        "A standoff, hon! No harm, no foul, no coin lost.",
        "Push it is, sugar. Boring, but painless.",
        "Neck and neck with the house, darlin' - nobody pays.",
        "A tie, hon. The house exhales, you keep your stack.",
        "A push, sugar - nobody wins, nobody weeps.",
        "Tied the house, darlin'. Your gold stays home.",
        "Push it is, hon! Painless as a game gets.",
        "Dead even, sugar - the house shrugs, you shrug.",
        "A wash, darlin'! Not a coin gained or lost.",
        "Standoff, hon - live to bet another hand.",
        "A push, sugar - nobody wins, nobody weeps.",
        "Tied the dealer, darlin' - your gold stays put.",
        "Push, hon - painless as this game gets!",
        "Dead even, sugar - the house shrugs, so do you.",
        "A wash, darlin' - not a coin lost, not a coin gained.",
        "Standoff, hon - live to bet another hand!",
    ],
    # Blackjack: you doubled down
    "bj_double": [
        "Doublin' down?! Ooh, I like your nerve, sugar.",
        "Big bet, one card - bold move, darlin'.",
        "Down goes double! Fortune favors the reckless, hon.",
        "Doublin' the stakes, sugar? Let's see it pay off.",
        "That's confidence, darlin'. Double or nothin'.",
        "Ooh, goin' for the double! Hold my drink, hon.",
        "Double down! Somebody woke up brave today, sugar.",
        "Twice the bet, one lonely card - gutsy, darlin'.",
        "Doublin'! I do love a gambler with sand, hon.",
        "You're doublin' down, sugar? The house leans in.",
        "Big swing! Double the gold, double the drama, darlin'.",
        "Doublin' down, hon - one card to glory or grief.",
        "Doublin' down, sugar?! I love a gambler with sand.",
        "Twice the bet, one card, darlin' - glory or grief!",
        "Down goes double, hon! Reckless, and I respect it.",
        "Big swing, sugar - double the gold, double the drama.",
        "Doublin' the stakes, darlin'! Hold my drink and pray.",
        "Ooh, a double! Somebody woke up brave, hon.",
        "Doublin' down, sugar? Now that's a spine!",
        "Twice the bet, one lonely card, darlin' - glory or grief!",
        "Down goes double, hon - reckless and I love it!",
        "Big swing, sugar - double the gold, double the sweat!",
        "Doublin' the stakes, darlin' - hold my drink and pray!",
        "Ooh, a double! Somebody's feelin' fearless, hon.",
    ],
    # Poker: cards hit the table at showdown
    "poker_showdown": [
        "Showdown, sugar! Cards on the table, no more hidin'.",
        "Here comes the reveal, darlin'. Read 'em and weep.",
        "Showdown time! Let's see who was bluffin', hon.",
        "Cards up, sugar. The moment of truth.",
        "Lay 'em down, darlin' - showdown!",
        "The reveal! My favorite part, hon. Who's got it?",
        "Showdown, sugar - all those poker faces come off now.",
        "Cards on the felt, darlin'! Truth time.",
        "Here we go - showdown, hon! Bluffers beware.",
        "Flip 'em over, sugar. Let's crown a winner.",
        "The bluffs are done, darlin' - cards up, showdown!",
        "Moment of truth, hon! Turn 'em over and pray.",
        "Showdown, sugar - poker faces off, truth on!",
        "Cards up, darlin' - the moment every bluffer dreads.",
        "Here comes the reveal, hon! Read 'em and weep.",
        "Flip 'em, sugar - let's crown somebody a winner.",
        "Showdown time, darlin'! All those secrets spill now.",
        "Lay 'em down, hon - truth or bust.",
        "Showdown, sugar - the poker faces come clean off!",
        "Cards up, darlin' - the moment the bluffers dread!",
        "Here's the reveal, hon - read 'em and weep!",
        "Flip 'em over, sugar - let's find our winner!",
        "Showdown time, darlin' - the secrets all spill now!",
        "Lay 'em down, hon - truth or bust!",
    ],
    # Crash: the zeppelin lifts off
    "crash_takeoff": [
        "And she's off! Ride her brave, sugar.",
        "Liftoff, darlin'! Remember - she always blows.",
        "Up, up she goes! Pick your moment, hon.",
        "The zeppelin's airborne, sugar. Nerve of steel now.",
        "Here we go! Don't ride her too long, darlin'.",
        "Wheels up! The higher she climbs, the sweeter... and scarier, hon.",
        "She's climbin', sugar! Watch that altitude and your nerve.",
        "Off the mast and into the sky, darlin' - hold tight!",
        "Takeoff! The pot grows every second, hon. So does the danger.",
        "Up she goes, sugar! Greed says higher, wisdom says jump.",
        "Airborne, darlin'! The clock's tickin' toward a boom.",
        "And liftoff! Choose your exit, hon - she won't wait forever.",
        "And she's climbin', sugar - pick your moment!",
        "Liftoff, darlin'! Remember, she always blows.",
        "Up she goes, hon - the pot grows and so does the danger.",
        "Airborne, sugar! Nerve of steel from here on.",
        "Wheels up, darlin' - jump smart, not late!",
        "Here we go, hon - away she flies and the clock's tickin'.",
        "And she's away, sugar - pick your moment wisely!",
        "Liftoff, darlin' - she always blows, remember that!",
        "Up she climbs, hon - the pot swells, so does the peril!",
        "Airborne, sugar - steady nerves from here on out!",
        "Wheels up, darlin' - jump smart, never late!",
        "Off she soars, hon - and the countdown to boom begins!",
    ],
    # Crash: she escaped off the screen (fly-away)
    "crash_flyaway": [
        "She flew away clean! Never even saw the crash, sugar.",
        "Off into the night she goes, darlin' - fly-away!",
        "Would you look at that, she made it out! Rare sight, hon.",
        "Fly-away! The old girl cheated fate this time, sugar.",
        "Gone, clean over the horizon! Lucky flight, darlin'.",
        "No boom tonight, hon - she flew away!",
        "The zeppelin escaped, sugar! Never thought I'd see it.",
        "Fly-away, darlin'! She sailed right off the edge, whole and hearty.",
        "Clean getaway! No crash, no boom, just gone, hon.",
        "Well I'll be - a fly-away, sugar! The house is stunned.",
        "She slipped the reaper and flew off, darlin'. Rare and pretty.",
        "Off she soars, no fireball tonight, hon - fly-away!",
        "A fly-away, sugar! She slipped the reaper clean.",
        "Off over the horizon, darlin' - no boom tonight!",
        "She made it out, hon! Rare and lovely sight.",
        "Clean getaway, sugar - the old girl cheated fate.",
        "Fly-away, darlin'! No fireball, just gone.",
        "Would you look at that, hon - she flew off whole and hearty!",
        "A fly-away, sugar - she gave the reaper the slip!",
        "Off past the horizon, darlin' - no boom for her tonight!",
        "She made it clean out, hon - what a rare, pretty sight!",
        "Clean getaway, sugar - the old girl cheated fate again!",
        "Fly-away, darlin' - no fireball, just gone into the blue!",
        "Would you look, hon - she flew off whole and hearty!",
    ],
    # table flow: the pre-deal countdown starts
    "countdown": [
        "Here we go - find your seats, sugar!",
        "Countin' 'em down, darlin' - last call for bets!",
        "Table's fillin' up! Get ready, hon.",
        "Almost time - buckle up, sugar!",
        "Here it comes, darlin'. Deal's about to drop.",
        "Get set, hon - the cards are itchin' to fly!",
        "Seats, everyone! We're startin' up, sugar.",
        "Last call, darlin' - in or out, decide quick!",
        "Countdown's on, hon! Steady your nerves.",
        "Any second now, sugar. Chips ready?",
        "Here we go, darlin' - the table's comin' to life!",
        "Almost showtime, hon - grab your spot!",
        "Here we go, sugar - find your seats!",
        "Last call, darlin' - in or out, decide quick!",
        "Table's comin' alive, hon - get ready!",
        "Countin' down, sugar - chips at the ready?",
        "Almost showtime, darlin' - grab your spot!",
        "Any second now, hon - the deal's about to drop.",
        "Here we go, sugar - seats, everyone!",
        "Last call, darlin' - in or out, quick now!",
        "The table's wakin' up, hon - ready yourself!",
        "Countin' down, sugar - chips at the ready?",
        "Almost showtime, darlin' - claim your spot!",
        "Any second, hon - the cards are itchin' to fly!",
    ],
    # Poker: YOU fold (personal, teasing, plays rarely)
    "poker_fold": [
        "Foldin' already, sugar? Cautious little thing.",
        "Layin' it down, darlin'? Live to bluff another hand.",
        "Ooh, throwin' in the towel, hon. Smart or scared?",
        "Fold it up, sweetheart - discretion's a virtue, they say.",
        "Mucked 'em, sugar? Can't win what you don't lose, I s'pose.",
        "Backin' out, darlin'? I'll pretend I didn't see that.",
        "Foldin', hon? Sometimes the bravest move is runnin' away.",
        "Tossin' the hand, sugar. No shame in a tactical retreat.",
        "Foldin' like fresh laundry, darlin'. Careful as ever.",
        "You're out this one, hon? Keepin' your powder dry, I see.",
        "Muck it, sugar - some hands ain't worth the heartache.",
        "Foldin' again, darlin'? The table's gettin' comfortable with that.",
        "Foldin' again, sugar? Careful as ever, I see.",
        "Layin' it down, darlin' - live to bluff another hand.",
        "Muckin' 'em, hon? Sometimes retreat's the smart play.",
        "Tossin' the hand, sugar - discretion's a virtue, they say.",
        "Foldin', darlin'? Keepin' your powder dry, clever thing.",
        "Out this one, hon? Can't lose what you don't play, I s'pose.",
        "Foldin' again, sugar? Cautious as a cat, you.",
        "Layin' it down, darlin' - live to bluff another day.",
        "Muckin' 'em, hon? Sometimes runnin' IS the play.",
        "Tossin' the hand, sugar - keepin' your gold and your secrets.",
        "Foldin', darlin'? Powder stays dry, I see.",
        "Out this one, hon? Can't lose what you never risk.",
    ],
    # Crash: the zeppelin climbs into the dangerous high air (~500m+)
    "crash_high": [
        "She's gettin' up there, sugar - this is where it turns wicked!",
        "Ooh, high and mighty now, darlin'. Every tick's a gamble.",
        "Look how high she's climbin'! My heart's in my throat, hon.",
        "Rarefied air up here, sugar - one more tick could be the last.",
        "She's way up now, darlin'! Greedy, greedy... jump while you can.",
        "Sky-high, hon! The pot's fat and the boom's overdue.",
        "That's dangerous altitude, sugar - fortune or fireball from here.",
        "She's soarin', darlin'! Every second's a dare now.",
        "Up in the thin air, hon - this is where legends and losers part ways.",
        "Climbin' into the danger zone, sugar! Nerve holdin' up?",
        "So high the pot's makin' me dizzy, darlin'. Jump or pray.",
        "She's really up there now, hon - the boom's just itchin' to happen.",
        "She's way up there, sugar - fortune or fireball from here!",
        "Dangerous altitude, darlin' - every tick's a dare now.",
        "So high the pot's makin' me dizzy, hon - jump or pray!",
        "Climbin' into thin air, sugar - legends part from losers here.",
        "She's soarin', darlin'! The boom's just itchin' to happen.",
        "Sky-high now, hon - greedy, greedy, mind that nerve!",
        "She's up in the clouds now, sugar - fortune or fireball!",
        "Dangerous heights, darlin' - every tick's a coin flip with the reaper.",
        "So high the pot's dizzy, hon - jump or pray, quick!",
        "Climbin' into thin air, sugar - the brave get rich or burned here.",
        "She's soarin', darlin' - and that boom's overdue!",
        "Sky-high, hon - greedy, greedy, mind your nerve!",
    ],
    # Hold'em tournament: a champion is crowned (winner-take-all)
    "tourney_champ": [
        "We got ourselves a champion, sugar! Last stack standin' takes it all!",
        "Winner winner, darlin' - the whole pool goes to one lucky soul!",
        "That's the tournament, hon! One player, every chip, every buy-in!",
        "The last stack standin'! Take a bow, sugar - you earned that pot.",
        "Crowned! The champ scoops the lot, darlin'. What a run!",
        "And that's all she wrote, hon - our champion takes the whole prize!",
        "Ladies and gents, your champion, sugar! Every last chip is theirs!",
        "The field's been conquered, darlin' - one winner takes everything!",
        "Tournament's done and dusted, hon! Bow to the last stack standin'!",
        "A champion is crowned, sugar! The whole pool, in one lucky lap!",
        "Last player breathin', darlin' - the buy-ins all come home to them!",
        "That's your winner, hon! Fought through the whole field for the lot!",
        "We got a champion, sugar - the whole pool, one lucky soul!",
        "Last stack standin', darlin'! Take a bow and the buy-ins.",
        "That's your winner, hon - fought the whole field for it!",
        "Crowned at last, sugar! Every chip comes home to one.",
        "The tournament's conquered, darlin' - bow to the champ!",
        "One player, every buy-in, hon - that's a champion!",
        "A champion's crowned, sugar - the whole pool, one lucky soul!",
        "Last stack standin', darlin' - take your bow and the buy-ins!",
        "That's your winner, hon - conquered the whole field!",
        "Crowned at last, sugar - every chip marches home to one!",
        "The tournament's done, darlin' - bow to the champ!",
        "One player, every buy-in, hon - a true champion!",
    ],
    # Hold'em tournament: a player is eliminated (busted out of chips)
    "tourney_bustout": [
        "And another one's out! No chips, no seat, sugar.",
        "Busted flat, darlin' - that's the end of their tournament.",
        "Ooh, eliminated! The field's gettin' thinner, hon.",
        "Out of chips, out the door, sugar. Better luck next buy-in.",
        "Down and out, darlin'! One fewer stack to worry about.",
        "That's a bust-out, hon - the survivors just got richer.",
        "Another stack bites the dust, sugar! The rail's fillin' up.",
        "Eliminated, darlin' - no chips left to fight with.",
        "There goes another contender, hon. The pyramid narrows.",
        "Chips all gone, sugar - that's a seat freed up.",
        "Bust-out! One more dreamer heads for the rail, darlin'.",
        "Out they go, hon - the tournament claims another stack.",
        "Another one hits the rail, sugar - no chips, no seat.",
        "Busted out, darlin'! The field grows thinner.",
        "Eliminated, hon - the survivors just got richer.",
        "Chips all gone, sugar - that's a seat freed up.",
        "Down and out, darlin'! One fewer stack to fear.",
        "There goes another dreamer, hon - the rail's fillin' up.",
        "Another hits the rail, sugar - no chips, no chair!",
        "Busted out, darlin' - the field thins again!",
        "Eliminated, hon - the survivors just got richer!",
        "Chips all gone, sugar - one more seat freed up!",
        "Down and out, darlin' - one fewer stack to fear!",
        "There goes a dreamer, hon - the rail's gettin' crowded!",
    ],
}

# Special one-offs that keep their historical filenames (not numbered pools).
SPECIAL = {
    "trix_intro": "Well hey there, sugar! Name's Trixie, and I'll be your host here at Chairface's Casino. Cards, dice, slots, ponies - if you can bet on it, we got it. Now let's see if Lady Luck likes the look of you.",
    "trix_poke1": "Hey now, watch the hands, sugar!",
    "trix_poke2": "Ooh, feelin' frisky are we, darlin'?",
    "trix_poke3": "Poke me again and I'll deal you a real bad hand, hon.",
    "trix_poke4": "Careful, sweetheart - I bite.",
}

# Generation priority = POOLS insertion order (frequent categories are declared
# first). Specials go last.
CAT_ORDER = {cat: i for i, cat in enumerate(POOLS)}


def build_lines():
    lines = dict(SPECIAL)
    for cat, arr in POOLS.items():
        for i, text in enumerate(arr, 1):
            lines[f"trix_{cat}{i}"] = text
    return lines


LINES = build_lines()

_NAME_RE = re.compile(r"^trix_(.+?)(\d+)$")


def parse_name(name):
    """trix_<cat><n> -> (cat, n). Non-numbered specials -> (rest, 0)."""
    m = _NAME_RE.match(name)
    if m:
        return m.group(1), int(m.group(2))
    return (name[len("trix_"):] if name.startswith("trix_") else name), 0


def sort_key(name):
    cat, idx = parse_name(name)
    # frequent categories first (CAT_ORDER), specials last (999), then
    # numeric index so each category fills 1..N contiguously.
    return (CAT_ORDER.get(cat, 999), cat, idx)


def api_get(path, key):
    req = urllib.request.Request(API + path, headers={"xi-api-key": key})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def find_voice_id(key):
    override = os.environ.get("ELEVENLABS_VOICE_ID")
    if override:
        return override
    data = api_get("/voices", key)
    for v in data.get("voices", []):
        if v.get("name", "").strip().lower() == VOICE_NAME.lower():
            return v["voice_id"]
    names = ", ".join(v.get("name", "?") for v in data.get("voices", []))
    sys.exit(f"Voice '{VOICE_NAME}' not found. Available: {names}\n"
             f"Add Arabella to your Voices, or set ELEVENLABS_VOICE_ID=<id>.")


def tts(voice_id, key, text):
    body = json.dumps({"text": text, "model_id": MODEL_ID,
                       "voice_settings": VOICE_SETTINGS}).encode("utf-8")
    url = f"{API}/text-to-speech/{voice_id}?output_format={OUTPUT_FORMAT}"
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "xi-api-key": key, "Content-Type": "application/json",
        "Accept": "audio/mpeg"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def exists(name):
    return (os.path.exists(os.path.join(OUT_DIR, name + ".ogg"))
            or os.path.exists(os.path.join(OUT_DIR, name + ".mp3")))


def disk_count(cat):
    """Largest N such that trix_<cat>1..N ALL exist (contiguous from 1)."""
    n = 0
    while exists(f"trix_{cat}{n + 1}"):
        n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="regenerate existing clips")
    ap.add_argument("--only", help="comma-separated categories (e.g. win,open_crash)")
    ap.add_argument("--counts", action="store_true", help="TARGET counts (POOLS lengths)")
    ap.add_argument("--counts-disk", action="store_true",
                    help="ACHIEVED counts from files on disk -> paste into Lobby.TRIXIE_VOICE")
    ap.add_argument("--list-voices", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.counts:
        print("-- TARGET (POOLS lengths); generate toward this, but set Lua from --counts-disk")
        for cat, arr in POOLS.items():
            print(f"    {cat} = {len(arr)},")
        print(f"  (+ specials: {', '.join(SPECIAL)})")
        return

    if args.counts_disk:
        print("-- Lobby.TRIXIE_VOICE (from files ACTUALLY on disk):")
        total = 0
        for cat in POOLS:
            n = disk_count(cat)
            total += n
            print(f"    {cat} = {n},")
        print(f"  -- total {total} category clips on disk")
        return

    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key and not args.dry_run:
        sys.exit("Set ELEVENLABS_API_KEY first (see header of this file).")

    if args.list_voices:
        for v in api_get("/voices", key).get("voices", []):
            print(f"  {v.get('name','?'):<24} {v.get('voice_id')}")
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    cats = [c.strip() for c in args.only.split(",")] if args.only else None

    def in_scope(name):
        if not cats:
            return True
        return any(name.startswith("trix_" + c) for c in cats)

    todo = [n for n in LINES if in_scope(n) and (args.force or not exists(n))]
    todo.sort(key=sort_key)   # frequent categories first, contiguous per category

    print(f"Output: {OUT_DIR}")
    print(f"{len(todo)} clip(s) to generate" + (" (dry run)" if args.dry_run else "") + ":")
    for n in todo:
        print(f"  {n}.mp3  <- \"{LINES[n]}\"")
    if args.dry_run or not todo:
        return

    voice_id = find_voice_id(key)
    print(f"Using voice '{VOICE_NAME}' ({voice_id}), model {MODEL_ID}\n")

    ok = 0
    for i, name in enumerate(todo, 1):
        try:
            audio = tts(voice_id, key, LINES[name])
            with open(os.path.join(OUT_DIR, name + ".mp3"), "wb") as f:
                f.write(audio)
            print(f"[{i}/{len(todo)}] {name}.mp3  ({len(audio)} bytes)")
            ok += 1
        except urllib.error.HTTPError as e:
            detail = ""
            try:
                detail = e.read().decode("utf-8", "replace")
            except Exception:
                pass
            low = detail.lower()
            # Quota exhausted (ElevenLabs reports this as 401 quota_exceeded or
            # a 402/429). Stop cleanly - the rest waits for next month's budget.
            if "quota" in low or e.code == 402 or ("credit" in low and "insufficient" in low):
                print(f"[{i}/{len(todo)}] {name}  BUDGET REACHED ({e.code}). "
                      f"Stopping; re-run when your quota resets.")
                break
            if e.code == 401 and i == 1:
                sys.exit(f"401 Unauthorized on the first call - the API key is invalid "
                         f"or rotated. Set a current ELEVENLABS_API_KEY.\n{detail[:200]}")
            if e.code == 429:
                print(f"[{i}/{len(todo)}] {name}  rate-limited (429), backing off 5s...")
                time.sleep(5)
                # one retry
                try:
                    audio = tts(voice_id, key, LINES[name])
                    with open(os.path.join(OUT_DIR, name + ".mp3"), "wb") as f:
                        f.write(audio)
                    print(f"[{i}/{len(todo)}] {name}.mp3  ({len(audio)} bytes) [retry]")
                    ok += 1
                    continue
                except Exception as e2:
                    print(f"[{i}/{len(todo)}] {name}  retry failed: {e2}")
                    continue
            print(f"[{i}/{len(todo)}] {name}  HTTP {e.code}: {detail[:200]}")
        except Exception as e:
            print(f"[{i}/{len(todo)}] {name}  ERROR: {e}")
        time.sleep(0.3)

    print(f"\nDone: {ok}/{len(todo)} generated into {OUT_DIR}")
    print("Now sync Lua counts:  python tools/gen_trixie_voices.py --counts-disk")
    print("Then restart the WoW client (a /reload won't load new audio files).")


if __name__ == "__main__":
    main()
