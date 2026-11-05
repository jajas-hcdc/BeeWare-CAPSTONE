import React, { createContext, useContext, useState, useEffect } from 'react';
import { 
  signInWithEmailAndPassword, 
  signOut, 
  onAuthStateChanged,
  createUserWithEmailAndPassword,
  updateProfile
} from 'firebase/auth';
import { doc, getDoc, setDoc, onSnapshot, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '../firebase';

const AuthContext = createContext();

export function useAuth() {
  return useContext(AuthContext);
}

export function AuthProvider({ children }) {
  const [currentUser, setCurrentUser] = useState(null);
  const [userProfile, setUserProfile] = useState(null);
  const [userRole, setUserRole] = useState(null);
  const [loading, setLoading] = useState(true);
  const [authLoading, setAuthLoading] = useState(false);
  const [authLoadingMessage, setAuthLoadingMessage] = useState('');
  const [authError, setAuthError] = useState(null);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (user) => {
      if (user) {
        setCurrentUser(user);
        
        // Listen to live user profile from Firestore /users/{uid}
        const userDocRef = doc(db, 'users', user.uid);
        const unsubProfile = onSnapshot(userDocRef, async (docSnap) => {
          if (docSnap.exists()) {
            const data = docSnap.data();
            setUserProfile(data);
            setUserRole(data.role || 'beekeeper');
          } else {
            // First time login - initialize user record with role based on email or default beekeeper
            let initialRole = 'beekeeper';
            const cleanEmail = (user.email || '').toLowerCase().trim();
            if (cleanEmail.includes('owner')) initialRole = 'owner';
            else if (cleanEmail.includes('admin')) initialRole = 'admin';
            else if (cleanEmail.includes('beekeeper')) initialRole = 'beekeeper';

            const newProfile = {
              email: user.email,
              displayName: user.displayName || user.email.split('@')[0],
              role: initialRole,
              createdAt: serverTimestamp(),
              lastLogin: serverTimestamp(),
              status: 'active'
            };
            await setDoc(userDocRef, newProfile, { merge: true });
            setUserProfile(newProfile);
            setUserRole(initialRole);
          }
          setLoading(false);
          setAuthLoading(false);
          setAuthLoadingMessage('');
        }, (err) => {
          console.error("Firestore user profile error:", err);
          setLoading(false);
          setAuthLoading(false);
          setAuthLoadingMessage('');
        });

        return () => unsubProfile();
      } else {
        setCurrentUser(null);
        setUserProfile(null);
        setUserRole(null);
        setLoading(false);
      }
    });

    return unsubscribe;
  }, []);

  async function login(email, password) {
    setAuthError(null);
    setAuthLoading(true);
    setAuthLoadingMessage('Authenticating operator credentials...');
    try {
      const res = await signInWithEmailAndPassword(auth, email, password);
      setAuthLoadingMessage('Loading apiary telemetry & dashboard...');
      await new Promise(resolve => setTimeout(resolve, 600));
      return res.user;
    } catch (err) {
      setAuthLoading(false);
      setAuthLoadingMessage('');
      setAuthError(err.message || 'Failed to sign in');
      throw err;
    }
  }

  async function registerAccount(email, password, displayName, role = 'beekeeper') {
    setAuthError(null);
    try {
      // Determine role based on email or provided role
      let finalRole = role || 'beekeeper';
      const cleanEmail = (email || '').toLowerCase().trim();
      if (cleanEmail.includes('owner')) {
        finalRole = 'owner';
      } else if (cleanEmail.includes('admin')) {
        finalRole = 'admin';
      } else if (cleanEmail.includes('beekeeper')) {
        finalRole = 'beekeeper';
      }

      const res = await createUserWithEmailAndPassword(auth, email, password);
      if (displayName) {
        await updateProfile(res.user, { displayName });
      }
      const userDocRef = doc(db, 'users', res.user.uid);
      const newProfile = {
        email,
        displayName: displayName || email.split('@')[0],
        role: finalRole,
        createdAt: serverTimestamp(),
        lastLogin: serverTimestamp(),
        status: 'active'
      };
      await setDoc(userDocRef, newProfile, { merge: true });
      setUserProfile(newProfile);
      setUserRole(finalRole);
      return res.user;
    } catch (err) {
      setAuthError(err.message || 'Failed to create account');
      throw err;
    }
  }

  async function logout() {
    setAuthError(null);
    setAuthLoading(true);
    setAuthLoadingMessage('Signing out of BeeWare Apiary Console...');
    try {
      await new Promise(resolve => setTimeout(resolve, 600));
      await signOut(auth);
    } catch (err) {
      console.error("Logout error:", err);
    } finally {
      setTimeout(() => {
        setAuthLoading(false);
        setAuthLoadingMessage('');
      }, 300);
    }
  }

  // Quick helper to claim Owner role (useful for capstone defense demo)
  async function claimOwnerRole() {
    if (!currentUser) return;
    const userDocRef = doc(db, 'users', currentUser.uid);
    await setDoc(userDocRef, { role: 'owner' }, { merge: true });
    setUserRole('owner');
  }

  const value = {
    currentUser,
    userProfile,
    userRole,
    isOwner: userRole === 'owner',
    isAdmin: userRole === 'admin' || userRole === 'owner',
    canPromoteUsers: userRole === 'owner',
    loading,
    authLoading,
    authLoadingMessage,
    authError,
    login,
    registerAccount,
    registerBeekeeper: registerAccount,
    logout,
    claimOwnerRole
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}
