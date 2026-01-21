// Import React hooks from the global React object (CDN usage)
const { useState, useEffect } = React;

// Regex de validación
const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const phoneRegex = /^\+?\d{9,15}$/;

function ContactApp() {
    
    // Each field is controlled by React state to keep the UI and data always in sync.
    const [name, setName] = useState("");
    const [reason, setReason] = useState("");
    const [email, setEmail] = useState("");
    const [phone, setPhone] = useState("");
    const [message, setMessage] = useState("");

    // Stores validation errors by field name (e.g., errors.email)
    const [errors, setErrors] = useState({});
    // Indicates whether the message was successfully sent (used to show confirmation text)
    const [sent, setSent] = useState(false);
    // Stores previously saved messages loaded from localStorage
    const [messages, setMessages] = useState([]);

    // Charge stored messages
    useEffect(() => {
        const saved = JSON.parse(localStorage.getItem("contactMessages")) || [];
        setMessages(saved);
    }, []);

    function handleSubmit(e) {
        e.preventDefault();

        let newErrors = {};

        // --- Required field validations ---
        if (!name.trim()) newErrors.name = "Name is required";
        if (!reason) newErrors.reason = "Select a reason";

        // --- Email validation ---
        if (!email.trim()) {
            newErrors.email = "Email is required";
        } else if (!emailRegex.test(email)) {
            newErrors.email = "Invalid email format";
        }

        // --- Phone validation ---
        if (!phone.trim()) {
            newErrors.phone = "Phone is required";
        } else if (!phoneRegex.test(phone)) {
            newErrors.phone = "Invalid phone format";
        }

        // --- Message validation ---
        if (!message.trim()) newErrors.message = "Message is required";

        // Save errors to state so the UI can display them
        setErrors(newErrors);

        // If there are any errors, stop the submission here
        if (Object.keys(newErrors).length > 0) return;

        // Build a new message entry including current timestamp
        const newMessage = {
            name,
            reason,
            email,
            phone,
            message,
            date: new Date().toLocaleString()
        };

        // Add new message to the existing list of messages
        let updatedMessages = [...messages, newMessage];

        // Keep only the last 5 messages (remove the oldest if we exceed 5)
        if (updatedMessages.length > 5) {
            updatedMessages.shift();
        }

        // Persist updated messages in localStorage (required by the assignment)
        localStorage.setItem(
            "contactMessages",
            JSON.stringify(updatedMessages)
        );

        // Update state to reflect the new list in the UI
        setMessages(updatedMessages);

        // Show "Message sent successfully"
        setSent(true);

        // Reset
        setName("");
        setReason("");
        setEmail("");
        setPhone("");
        setMessage("");
        setErrors({});
    }

    // Clear local storage messages
    function clearMessages() {
        localStorage.removeItem("contactMessages");
        setMessages([]);
    }

    return (
        <div>
            <h3 className="react-title">Contact Form</h3>

            {/* noValidate disables browser default validation so we can use our own validation logic */}
            <form onSubmit={handleSubmit} noValidate>

                <div className="field">
                    <label>Name *</label>
                    <input
                        value={name}

                        // Update state on every keystroke (controlled component)
                        onChange={e => {
                            setName(e.target.value);
                            setSent(false);
                        }}
                    />

                    {/* Show error message only if this field has an error */}
                    {errors.name && <div className="error">{errors.name}</div>}
                </div>

                <div className="field">
                    <label>Reason *</label>
                    <select
                        value={reason}
                        onChange={e => {
                            setReason(e.target.value);
                            setSent(false);
                        }}
                    >
                        <option value="">-- Select --</option>
                        <option value="Information">Information</option>
                        <option value="Complaint">Complaint</option>
                        <option value="Suggestion">Suggestion</option>
                        <option value="Other">Other</option>
                    </select>
                    {errors.reason && <div className="error">{errors.reason}</div>}
                </div>
                
                {/* Row layout: Email and Phone side by side */}
                <div className="row">
                    <div className="field">
                        <label>Email *</label>
                        <input
                            value={email}
                            onChange={e => {
                                setEmail(e.target.value);
                                setSent(false);
                            }}
                        />
                        {errors.email && <div className="error">{errors.email}</div>}
                    </div>

                    <div className="field">
                        <label>Phone *</label>
                        <input
                            value={phone}
                            onChange={e => {
                                setPhone(e.target.value);
                                setSent(false);
                            }}
                        />
                        {errors.phone && <div className="error">{errors.phone}</div>}
                    </div>
                </div>

                <div className="field">
                    <label>Message *</label>
                    <textarea
                        value={message}
                        onChange={e => {
                            setMessage(e.target.value);
                            setSent(false);
                        }}
                    />
                    {errors.message && <div className="error">{errors.message}</div>}
                </div>

                <button className="btn" type="submit">
                    Send Message
                </button>
            </form>
            
            {/* Confirmation text shown only after successful submit */}
            {sent && <p className="muted">Message sent successfully</p>}
            
            {/* Render saved messages only if there is at least one */}
            {messages.length > 0 && (
                <>
                    <div className="hr"></div>

                    {/* Header + clear button */}
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                        <h4>Saved messages</h4>
                        <button className="btn secondary" onClick={clearMessages}>
                            Clear
                        </button>
                    </div>

                    {/* List all saved messages */}
                    {messages.map((msg, index) => (
                        <div className="review" key={index}>
                            <div className="review-top">
                                <strong>{msg.name}</strong>
                                <span className="muted">{msg.date}</span>
                            </div>
                            <p className="muted">{msg.reason}</p>
                            <p>{msg.message}</p>
                        </div>
                    ))}
                </>
            )}
        </div>
    );
}

// Render the ContactApp component inside the element with id="react-root"
ReactDOM
    .createRoot(document.getElementById("react-root"))
    .render(<ContactApp />);
