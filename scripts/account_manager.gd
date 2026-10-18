extends Node

# AccountManager Autoload (res://scripts/account_manager.gd)
# Handles user registration, authentication (Sign in / Sign up / Sign out),
# profile persistence in user://accounts.json, Friends management by username,
# Party invite system, and Redeem Gift Codes.
# NOTE: Guest mode is completely removed; an account is mandatory.
# NOTE: ADMIN2026 is removed; Admin Hero is strictly unlocked by beating the Boss in-game.

signal user_logged_in(username: String)
signal user_logged_out()
signal friends_updated(friends_list: Array)
signal party_updated(party_members: Array)

const ACCOUNTS_FILE: String = "user://accounts.json"

var accounts_data: Dictionary = {
	"users": {},
	"current_user": ""
}

var current_party: Array = []

func _ready() -> void:
	load_accounts()
	if is_logged_in():
		current_party = [get_current_user()]
	else:
		current_party = []

func load_accounts() -> void:
	if not FileAccess.file_exists(ACCOUNTS_FILE):
		accounts_data = {
			"users": {},
			"current_user": ""
		}
		save_accounts()
		return
	
	var file = FileAccess.open(ACCOUNTS_FILE, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var json = JSON.new()
		var parse_result = json.parse(content)
		if parse_result == OK and typeof(json.data) == TYPE_DICTIONARY:
			accounts_data = json.data
			if not accounts_data.has("users"):
				accounts_data["users"] = {}
			# Remove legacy Guest if present
			if accounts_data["users"].has("Guest"):
				accounts_data["users"].erase("Guest")
			var cur = accounts_data.get("current_user", "")
			if cur == "Guest" or not accounts_data["users"].has(cur):
				accounts_data["current_user"] = ""
		file.close()

func save_accounts() -> void:
	var file = FileAccess.open(ACCOUNTS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(accounts_data, "\t"))
		file.close()

func is_logged_in() -> bool:
	var cur = accounts_data.get("current_user", "")
	return not cur.is_empty() and cur != "Guest" and accounts_data["users"].has(cur)

func get_current_user() -> String:
	return accounts_data.get("current_user", "")

func sign_up(user_name: String, pass_word: String) -> Dictionary:
	var u = user_name.strip_edges()
	var p = pass_word.strip_edges()
	
	if u.length() < 2:
		return {"success": false, "message": "⚠️ اسم المستخدم يجب أن يكون حرفين على الأقل!"}
	if p.length() < 3:
		return {"success": false, "message": "⚠️ كلمة المرور يجب أن تكون 3 أحرف/أرقام على الأقل!"}
	
	if accounts_data["users"].has(u):
		return {"success": false, "message": "⚠️ هذا الاسم مسجل بالفعل! جرب تسجيل الدخول أو اختر اسماً آخر."}
	
	# Register user
	accounts_data["users"][u] = {
		"password": p,
		"friends": [],
		"redeemed_codes": [],
		"created_at": Time.get_datetime_string_from_system()
	}
	accounts_data["current_user"] = u
	current_party = [u]
	save_accounts()
	
	user_logged_in.emit(u)
	friends_updated.emit(get_friends())
	party_updated.emit(current_party)
	return {"success": true, "message": "🎉 تم إنشاء الحساب وتسجيل الدخول كـ: " + u}

func sign_in(user_name: String, pass_word: String) -> Dictionary:
	var u = user_name.strip_edges()
	var p = pass_word.strip_edges()
	
	if not accounts_data["users"].has(u):
		return {"success": false, "message": "❌ اسم المستخدم غير موجود! يرجى إنشاء حساب جديد أولاً."}
	
	var user_record = accounts_data["users"][u]
	if user_record.get("password", "") != p:
		return {"success": false, "message": "❌ كلمة المرور غير صحيحة!"}
	
	accounts_data["current_user"] = u
	current_party = [u]
	save_accounts()
	
	user_logged_in.emit(u)
	friends_updated.emit(get_friends())
	party_updated.emit(current_party)
	return {"success": true, "message": "✅ مرحباً بك مجدداً، " + u + "!"}

func sign_out() -> void:
	accounts_data["current_user"] = ""
	current_party = []
	save_accounts()
	user_logged_out.emit()
	friends_updated.emit([])
	party_updated.emit([])

func get_friends() -> Array:
	var cur = get_current_user()
	if not cur.is_empty() and accounts_data["users"].has(cur):
		return accounts_data["users"][cur].get("friends", [])
	return []

func add_friend(friend_name: String) -> Dictionary:
	var cur = get_current_user()
	if not is_logged_in():
		return {"success": false, "message": "⚠️ يجب تسجيل الدخول بحساب أولاً لإضافة أصدقاء!"}
	
	var f = friend_name.strip_edges()
	if f.is_empty():
		return {"success": false, "message": "⚠️ اكتب اسم الصديق (Username) أولاً!"}
	if f == cur:
		return {"success": false, "message": "⚠️ لا يمكنك إضافة نفسك كصديق!"}
	
	var friends = get_friends()
	if friends.has(f):
		return {"success": false, "message": "ℹ️ %s موجود بالفعل في قائمة أصدقائك!" % f}
	
	friends.append(f)
	accounts_data["users"][cur]["friends"] = friends
	save_accounts()
	friends_updated.emit(friends)
	return {"success": true, "message": "✅ تمت إضافة %s إلى قائمة أصدقائك بنجاح!" % f}

func remove_friend(friend_name: String) -> void:
	var cur = get_current_user()
	if not is_logged_in() or not accounts_data["users"].has(cur):
		return
	var friends = get_friends()
	if friends.has(friend_name):
		friends.erase(friend_name)
		accounts_data["users"][cur]["friends"] = friends
		save_accounts()
		friends_updated.emit(friends)

func invite_to_party(friend_name: String) -> Dictionary:
	var cur = get_current_user()
	if not is_logged_in():
		return {"success": false, "message": "⚠️ سجل دخول أولاً لتكوين بارتي!"}
	
	if not current_party.has(cur):
		current_party = [cur]
	
	if current_party.has(friend_name):
		return {"success": false, "message": "ℹ️ %s موجود بالفعل في البارتي!" % friend_name}
	
	current_party.append(friend_name)
	party_updated.emit(current_party)
	return {"success": true, "message": "🎉 تم إرسال دعوة لـ %s وإضافته إلى البارتي الخاص بك!" % friend_name}

func leave_party() -> void:
	var cur = get_current_user()
	if cur.is_empty():
		current_party = []
	else:
		current_party = [cur]
	party_updated.emit(current_party)

func redeem_code(code_raw: String) -> Dictionary:
	var code = code_raw.strip_edges().to_upper().replace(" ", "").replace("#", "")
	if code.is_empty():
		return {"success": false, "message": "⚠️ يرجى كتابة كود الهدية أولاً!"}
	
	if not is_logged_in():
		return {"success": false, "message": "⚠️ يجب تسجيل الدخول بحساب لاسترداد الأكواد!"}
	
	var cur = get_current_user()
	var user_data = accounts_data["users"].get(cur, {})
	var redeemed_list: Array = user_data.get("redeemed_codes", [])
	
	if redeemed_list.has(code):
		return {"success": false, "message": "⚠️ لقد قمت باسترداد هذا الكود من قبل!"}
	
	var success = false
	var reward_text = ""
	
	match code:
		"BERRY2026", "BERRY":
			GameManager.unlock_hero(1) # Berry
			reward_text = "🍓 تم فتح بطلة الفراولة السريعة (Berry Striker) بنجاح!"
			success = true
		"CITRUS2026", "CITRUS", "ORANGE":
			GameManager.unlock_hero(2) # Citrus
			reward_text = "🍊 تم فتح البرتقال المدرّع العملاق (Citrus Defender) بنجاح!"
			success = true
		"ALLHEROES":
			GameManager.unlock_hero(1)
			GameManager.unlock_hero(2)
			reward_text = "🌟 تم فتح بطلة الفراولة والبرتقال المدرّع! (بطل الأدمن يُفتح فقط بالفوز وهزيمة البيج بوس في اللعبة!)"
			success = true
		"TITAN", "TITAN2026":
			reward_text = "⚡ تم تفعيل كود تايتان سترايك وفتح لقب تايتان النادر!"
			success = true
		"SPIDER", "SPIDER2026":
			reward_text = "🕷️ كود سبايدر نشط! استمتع بالقفز العالي وشباك العنكبوت!"
			success = true
		_:
			return {"success": false, "message": "❌ كود الهدية غير صحيح أو منتهي الصلاحية!"}
	
	if success:
		if accounts_data["users"].has(cur):
			redeemed_list.append(code)
			accounts_data["users"][cur]["redeemed_codes"] = redeemed_list
			save_accounts()
		return {"success": true, "message": reward_text}
	
	return {"success": false, "message": "❌ فشل استرداد الكود."}
