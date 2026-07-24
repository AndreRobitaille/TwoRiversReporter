import { Controller } from "@hotwired/stimulus"

const DEFAULT_URLS = {
  registrationOptions: "/passkeys/registration_options",
  registration: "/passkeys/registration",
  authenticationOptions: "/passkeys/authentication_options",
  authentication: "/passkeys/authentication"
}

export default class extends Controller {
  static targets = ["status", "trigger"]

  connect() {
    if (this.#supportsWebAuthn()) return

    this.triggerTargets.forEach((button) => {
      button.disabled = true
    })

    this.#setStatus("This browser doesn't support passkeys — use the email link instead.", "error")
  }

  register = async () => {
    await this.#runCeremony("register")
  }

  authenticate = async () => {
    await this.#runCeremony("authenticate")
  }

  async #runCeremony(kind) {
    if (!this.#supportsWebAuthn()) {
      this.#setStatus("Your browser doesn't support passkeys.", "error")
      return
    }

    try {
      if (kind === "register") {
        await this.#registerPasskey()
      } else {
        await this.#authenticateWithPasskey()
      }
    } catch (error) {
      this.#setStatus(error?.message || "That didn't work. Please try again.", "error")
    }
  }

  async #registerPasskey() {
    this.#setStatus("Preparing a new passkey…", "working")

    const response = await fetch(this.registrationOptionsUrl, {
      method: "POST",
      headers: this.#jsonHeaders()
    })

    if (!response.ok) {
      throw new Error("We couldn't load passkey settings right now.")
    }

    const options = this.#creationOptionsFromJSON(await response.json())
    this.#setStatus("Waiting for your device…", "working")

    const credential = await navigator.credentials.create({ publicKey: options })
    if (!credential) throw new Error("No passkey was created.")

    const saveResponse = await this.#postJSON(this.registrationUrl, {
      credential: this.#credentialToJSON(credential)
    })

    if (!saveResponse.ok) {
      throw new Error("We couldn't save that passkey.")
    }

    const payload = await this.#readJSON(saveResponse)
    this.#setStatus("Passkey saved. Reloading…", "success")
    window.location.assign(payload.redirect_to || payload.redirectTo || window.location.href)
  }

  async #authenticateWithPasskey() {
    this.#setStatus("Checking for a passkey…", "working")

    const response = await fetch(this.authenticationOptionsUrl, {
      method: "POST",
      headers: this.#jsonHeaders()
    })

    if (!response.ok) {
      throw new Error("We couldn't start sign-in right now.")
    }

    const options = this.#requestOptionsFromJSON(await response.json())
    this.#setStatus("Waiting for your passkey…", "working")

    const credential = await navigator.credentials.get({ publicKey: options })
    if (!credential) throw new Error("No passkey was used.")

    const signInResponse = await this.#postJSON(this.authenticationUrl, {
      credential: this.#credentialToJSON(credential)
    })

    const payload = await this.#readJSON(signInResponse)
    if (!signInResponse.ok) {
      throw new Error(payload.error || "We couldn't sign you in.")
    }

    this.#setStatus("Signed in. Redirecting…", "success")
    window.location.assign(payload.redirect_to || payload.redirectTo || "/")
  }

  async #postJSON(url, body) {
    return fetch(url, {
      method: "POST",
      headers: this.#jsonHeaders(),
      body: JSON.stringify(body)
    })
  }

  async #readJSON(response) {
    try {
      return await response.json()
    } catch {
      return {}
    }
  }

  #creationOptionsFromJSON(options) {
    if (window.PublicKeyCredential?.parseCreationOptionsFromJSON) {
      return PublicKeyCredential.parseCreationOptionsFromJSON(options)
    }

    return {
      ...options,
      challenge: this.#base64UrlToBuffer(options.challenge),
      user: {
        ...options.user,
        id: this.#base64UrlToBuffer(options.user.id)
      },
      excludeCredentials: (options.excludeCredentials || []).map((credential) => ({
        ...credential,
        id: this.#base64UrlToBuffer(credential.id)
      }))
    }
  }

  #requestOptionsFromJSON(options) {
    if (window.PublicKeyCredential?.parseRequestOptionsFromJSON) {
      return PublicKeyCredential.parseRequestOptionsFromJSON(options)
    }

    return {
      ...options,
      challenge: this.#base64UrlToBuffer(options.challenge),
      allowCredentials: (options.allowCredentials || []).map((credential) => ({
        ...credential,
        id: this.#base64UrlToBuffer(credential.id)
      }))
    }
  }

  #credentialToJSON(credential) {
    if (typeof credential.toJSON === "function") {
      return credential.toJSON()
    }

    return {
      id: credential.id,
      rawId: this.#bufferToBase64Url(credential.rawId),
      type: credential.type,
      response: this.#credentialResponseToJSON(credential.response),
      clientExtensionResults: credential.getClientExtensionResults?.() || {}
    }
  }

  #credentialResponseToJSON(response) {
    return {
      clientDataJSON: this.#bufferToBase64Url(response.clientDataJSON),
      attestationObject: response.attestationObject ? this.#bufferToBase64Url(response.attestationObject) : undefined,
      authenticatorData: response.authenticatorData ? this.#bufferToBase64Url(response.authenticatorData) : undefined,
      signature: response.signature ? this.#bufferToBase64Url(response.signature) : undefined,
      userHandle: response.userHandle ? this.#bufferToBase64Url(response.userHandle) : undefined
    }
  }

  #bufferToBase64Url(buffer) {
    const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer)
    let binary = ""

    bytes.forEach((byte) => {
      binary += String.fromCharCode(byte)
    })

    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
  }

  #base64UrlToBuffer(value) {
    if (value instanceof ArrayBuffer) return value
    if (ArrayBuffer.isView(value)) return value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength)

    const normalized = value.replace(/-/g, "+").replace(/_/g, "/")
    const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4)
    const binary = atob(padded)
    const bytes = new Uint8Array(binary.length)

    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index)
    }

    return bytes.buffer
  }

  #supportsWebAuthn() {
    return typeof window.PublicKeyCredential !== "undefined" && typeof navigator.credentials?.create === "function" && typeof navigator.credentials?.get === "function"
  }

  #jsonHeaders() {
    return {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-CSRF-Token": this.#csrfToken()
    }
  }

  #csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  #setStatus(message, state) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message || ""
    this.statusTarget.classList.remove(
      "auth-status--working",
      "auth-status--error",
      "auth-status--success"
    )

    if (state) this.statusTarget.classList.add(`auth-status--${state}`)
  }

  get registrationOptionsUrl() {
    return this.element.dataset.passkeyRegistrationOptionsUrlValue || DEFAULT_URLS.registrationOptions
  }

  get registrationUrl() {
    return this.element.dataset.passkeyRegistrationUrlValue || DEFAULT_URLS.registration
  }

  get authenticationOptionsUrl() {
    return this.element.dataset.passkeyAuthenticationOptionsUrlValue || DEFAULT_URLS.authenticationOptions
  }

  get authenticationUrl() {
    return this.element.dataset.passkeyAuthenticationUrlValue || DEFAULT_URLS.authentication
  }
}
