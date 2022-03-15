import { Cookie } from "./cookie"

export const ChangeLocaleHook = {
destroyed() {
    Cookie.set("locale", this.el.value)
}
}

let ChangeLocaleHooks = {};

ChangeLocaleHooks.ChangeLocaleHook = ChangeLocaleHook;

export { ChangeLocaleHooks } 