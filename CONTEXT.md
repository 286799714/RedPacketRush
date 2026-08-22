# Red Packet Rush

Red Packet Rush is a fixed four-participant card game built around scoring three-card combinations and secretly competing for the cards just played.

## Language

**Participant**:
One of the four seats in a match, controlled either by a human player or by a bot.
_Avoid_: User, client, member

**Lobby**:
The public list of joinable rooms and the place where a human participant chooses a temporary nickname.
_Avoid_: Room, match, home page

**Room**:
The four-seat waiting area where participants prepare and the host selects match settings before play begins.
_Avoid_: Lobby, match, table

**Host**:
The human participant who owns room configuration and start controls while the room is waiting.
_Avoid_: Actor, winner, server

**Match**:
One complete game from the point contest through final settlement for exactly four participants.
_Avoid_: Room, turn, round

**Deck mode**:
The room setting that uses either one or two identical 52-card packs without jokers.
_Avoid_: Player count, hand size

**Card rank**:
The value ordering `2 < 3 < ... < K < A`; A may be low only in `A-2-3` and high in `Q-K-A`.
_Avoid_: Card score

**Suit rank**:
The tie-break ordering `clubs < spades < diamonds < hearts`; when displayed strongest-first this is hearts, diamonds, spades, clubs.
_Avoid_: Card rank, combination score

**Point contest**:
A reveal draw used only to select the first actor; tied leaders draw again until unique, then all contest cards return to the deck before hands are dealt.
_Avoid_: Deal, opening hand

**Actor**:
The participant whose turn it is to play and score three cards.
_Avoid_: Host, room owner, winner

**Turn**:
One actor play, score, and draw followed by the other participants' simultaneous claims, claim resolution, required discards, and selection of the next actor.
_Avoid_: Round, match

**Combination**:
Three cards scored once as their highest category: high card, pair, flush, straight, three of a kind, or straight flush.
_Avoid_: Hand, meld

**Claim**:
A non-actor's secret choice to compete for one of the three cards played this turn.
_Avoid_: Draw, take, bid

**Pass**:
A non-actor's secret choice not to claim a played card, worth one point when choices are revealed.
_Avoid_: Fold, skip turn

**Collision**:
The resolution when multiple participants claim the same card: after unique awards are removed, collision participants each draw blindly from all remaining played cards.
_Avoid_: Tie, point contest

**Awarded card**:
A played card received through either a unique claim or a collision draw; its recipient must keep it for the current turn and discard a different card.
_Avoid_: Drawn card, played card

**Final settlement**:
The automatic endgame selection of the highest-scoring three-card combination from each participant's five-card hand, with the other two cards unused.
_Avoid_: Turn, point contest

**Bot**:
A server-controlled participant that occupies a normal seat and follows the same match rules as a human participant.
_Avoid_: Spectator, dummy card
