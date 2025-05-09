# ReviewItem.gd
extends PanelContainer

@onready var username_label: Label = $MarginContainer/ContentVBox/HBoxContainer/UsernameLabel
@onready var date_label: Label = $MarginContainer/ContentVBox/HBoxContainer/DateLabel
@onready var review_rating_stars: RatingStarsDisplay = $MarginContainer/ContentVBox/RatingContainer/ReviewRatingStars
@onready var review_text_label: Label = $MarginContainer/ContentVBox/ReviewTextLabel

func set_review_data(data: Dictionary):
	var username = data.get("user_display", "Anonym")
	if username:
		username_label.text = username

	var timestamp = data.get("date_created", 0)
	if timestamp > 0:
		var datetime_dict = Time.get_datetime_dict_from_unix_time(timestamp)
		date_label.text = "%02d.%02d.%04d" % [datetime_dict.day, datetime_dict.month, datetime_dict.year]
	else:
		date_label.text = ""
	
	var percentage_rating = data.get("rating", -1) 
	if percentage_rating >= 0 and percentage_rating <= 100 and is_instance_valid(review_rating_stars):
		var star_value = (float(percentage_rating) / 100.0) * float(review_rating_stars.max_stars)
		review_rating_stars.set_stars(star_value)
	elif is_instance_valid(review_rating_stars):
		review_rating_stars.set_stars(-1.0) # Signalisiert "kein Rating" / versteckt Sterne	
	
	review_text_label.text = data.get("description", "No Review text found.") # ODRS verwendet oft "review"
	# Falls der Key "review_text" in Ihren ODRS-Daten anders heißt (z.B. nur "review"), anpassen.
	# Beispiel ODRS: data.get("review", "Kein Review-Text vorhanden.")
