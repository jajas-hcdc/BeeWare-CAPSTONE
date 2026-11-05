import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getDatabase } from 'firebase/database';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY || "AIzaSyAEFlPmb4aEKPUCWw7DzHRQqKvM1rvfgXw",
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || "beeware-beaef.firebaseapp.com",
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID || "beeware-beaef",
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET || "beeware-beaef.firebasestorage.app",
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID || "242774020378",
  appId: import.meta.env.VITE_FIREBASE_APP_ID || "1:242774020378:web:2a14dc6dd3e78ff6099ca3",
  databaseURL: import.meta.env.VITE_FIREBASE_DATABASE_URL || "https://beeware-beaef-default-rtdb.asia-southeast1.firebasedatabase.app"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);

export const auth = getAuth(app);
export const db = getFirestore(app);
export const rtdb = getDatabase(app);

export default app;
