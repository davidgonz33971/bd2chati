# # ========================= =================================
# #  NOTIFICATIONS - USES MONGODB ONLY
# # ==========================================================
# from django.contrib.auth.decorators import login_required
# from django.http import JsonResponse
# # Import notification helper functions from notifications.py
# from ..notifications import get_user_notifications, mark_as_read

# @login_required
# def get_notifications(request):
#     """
#     API endpoint to retrieve ALL notifications for the currently logged-in user.
#     Only returns notifications from the last 2 minutes.

#     Returns:
#         JsonResponse: JSON object containing array of user's recent notifications
#     """
#     # Get the email of the currently logged-in user
#     user_email = request.user.email

#     # Fetch ALL notifications from the last 2 minutes
#     data = get_user_notifications(user_email)

#     # Return notifications as JSON response
#     return JsonResponse({"notifications": data})

# @login_required
# def mark_notification_read(request, notif_id):
#     """
#     API endpoint to mark a specific notification as read.
#     Args:
#         notif_id (str): MongoDB ObjectId as a string from URL parameter
#     Returns:
#         JsonResponse: JSON object with status "ok" or "error"
#     """
#     # Attempt to mark the notification as read using helper function
#     success = mark_as_read(notif_id)
#     # Return success or error status
#     if success:
#         return JsonResponse({"status": "ok"})
#     else:
#         return JsonResponse({"status": "error"})