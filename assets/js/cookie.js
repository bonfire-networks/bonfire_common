export const Cookie = (document => {

  return { set: set }

  function set(name, locale) {
    document.cookie = `${name}=${locale}; expires=${expires()}`
  }

  function expires() {
    let expiry = new Date()
    // Set expiry to ten days
    expiry.setDate(expiry.getDate() + 10)
    return expiry.toGMTString()
  }
})(document)