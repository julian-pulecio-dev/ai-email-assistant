import { useGoogleLogin } from "@react-oauth/google";
import { useState } from "react";
import { Navigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

// openid/email/profile give us identity; gmail.modify lets the backend read
// and update (mark read, archive, etc.) the user's Gmail on their behalf.
const GOOGLE_SCOPES = "openid email profile https://www.googleapis.com/auth/gmail.modify";

export function LoginPage() {
  const { user, loginWithGoogleAuthCode } = useAuth();
  const [error, setError] = useState<string | null>(null);

  const login = useGoogleLogin({
    flow: "auth-code",
    scope: GOOGLE_SCOPES,
    onSuccess: async (codeResponse) => {
      setError(null);
      try {
        await loginWithGoogleAuthCode(codeResponse.code);
      } catch {
        setError("Sign-in failed. Please try again.");
      }
    },
    onError: () => setError("Google sign-in failed."),
  });

  if (user) {
    return <Navigate to="/dashboard" replace />;
  }

  return (
    <div className="login-page">
      <h1>Sign in</h1>
      <p>
        This app only supports signing in with your Google account. You'll also be asked to grant access to your
        Gmail so the app can read and organize your messages on your behalf.
      </p>
      <button onClick={() => login()}>Sign in with Google</button>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
