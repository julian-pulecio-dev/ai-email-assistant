import { useState } from "react";
import { fetchGmailMessages, type GmailMessage } from "../api/client";
import { useAuth } from "../context/AuthContext";

export function Dashboard() {
  const { user, token, logout } = useAuth();
  const [messages, setMessages] = useState<GmailMessage[] | null>(null);
  const [loadingMessages, setLoadingMessages] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!user || !token) {
    return null;
  }

  async function handleLoadMessages() {
    setError(null);
    setLoadingMessages(true);
    try {
      setMessages(await fetchGmailMessages(token!));
    } catch {
      setError("Could not load Gmail messages. You may need to sign in again to re-grant access.");
    } finally {
      setLoadingMessages(false);
    }
  }

  return (
    <div className="dashboard">
      <h1>Welcome, {user.name}</h1>
      <img
        src={user.picture}
        alt={user.name}
        width={80}
        height={80}
        referrerPolicy="no-referrer"
        onError={(e) => {
          e.currentTarget.style.display = "none";
        }}
      />
      <p>{user.email}</p>
      <button onClick={logout}>Log out</button>

      <hr style={{ width: "100%" }} />

      <button onClick={handleLoadMessages} disabled={loadingMessages}>
        {loadingMessages ? "Loading..." : "Load recent emails"}
      </button>
      {error && <p className="error">{error}</p>}
      {messages && (
        <ul style={{ textAlign: "left", width: "100%", maxWidth: 480 }}>
          {messages.map((message) => (
            <li key={message.id}>
              <strong>{message.subject}</strong>
              <br />
              <small>{message.from}</small>
              <p>{message.snippet}</p>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
