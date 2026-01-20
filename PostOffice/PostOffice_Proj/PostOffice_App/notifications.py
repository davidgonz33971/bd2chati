from django.utils import timezone
from pymongo import MongoClient
from bson import ObjectId
from datetime import timedelta

# ==========================================================
#  MONGO: NOTIFICATIONS ONLY - CENTRALIZED CONNECTION
# ==========================================================

# Access the 'notifications' collection within the database
mongo_client = MongoClient("mongodb://localhost:27017")
mongo_db = mongo_client["postoffice"]
notifications_collection = mongo_db["notifications"]


def create_notification(notification_type, recipient_contact, subject, message, status="pending"):
    """
    Creates a new notification document in MongoDB.

    Args:
        notification_type (str): Type of notification (e.g., 'delivery_update', 'route_assigned')
        recipient_contact (str): Email address of the recipient user
        subject (str): Subject/title of the notification
        message (str): Main notification message to display
        status (str): Current status of the notification (default: 'pending')

    Returns:
        None - Silently fails if MongoDB is unavailable
    """
    try:
        # Insert a new notification document into MongoDB
        notifications_collection.insert_one({
            "notification_type": notification_type,  # Category of notification
            "recipient_contact": recipient_contact,   # User's email to match against
            "subject": subject,                       # Notification title
            "message": message,                       # Main content to display
            "status": status,                         # Processing status
            "is_read": False,                         # Initially unread
            "created_at": timezone.now(),             # Timestamp of creation
        })
    except Exception:
        # Silently fail to avoid breaking the main application flow
        # In production, you might want to log this error
        pass


def get_user_notifications(user_email, max_age_minutes=3):
    """
    Retrieves all recent notifications for a specific user from MongoDB.
    Only returns notifications created within the last X minutes.

    Args:
        user_email (str): Email address of the user
        max_age_minutes (int): Only show notifications from the last X minutes (default: 2)

    Returns:
        list: List of notification dictionaries with formatted data
    """
    # Calculate the cutoff time (e.g., 3 minutes ago)
    cutoff_time = timezone.now() - timedelta(minutes=max_age_minutes)

    # Query MongoDB for ALL notifications matching the user's email AND created after cutoff
    notifs = list(
        notifications_collection.find({
            "recipient_contact": user_email,
            "created_at": {"$gte": cutoff_time}  # Only get notifications newer than cutoff
        })
        .sort("created_at", -1)  # Sort by creation date, newest first
    )

    # Format the notifications for JSON response
    data = []
    for n in notifs:
        data.append({
            "id": str(n["_id"]),                                    # Convert ObjectId to string
            "message": n.get("message", ""),                        # Get message or empty string
            "is_read": n.get("is_read", False),                     # Get read status or False
            "created_at": n["created_at"].strftime("%d/%m %H:%M")  # Format datetime as string
        })

    return data


def mark_as_read(notif_id):
    """
    Marks a specific notification as read in MongoDB.
    Args:
        notif_id (str): String representation of the MongoDB ObjectId
    Returns:
        bool: True if notification was successfully marked as read, False otherwise
    """
    try:
        # Update the notification document, setting is_read to True
        result = notifications_collection.update_one(
            {"_id": ObjectId(notif_id)},  # Find notification by ObjectId
            {"$set": {"is_read": True}}    # Set is_read field to True
        )
        # Return True if at least one document was modified
        return result.modified_count > 0
    except Exception:
        # Return False if ObjectId is invalid or any other error occurs
        return False