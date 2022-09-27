print "enter your expression:"
    local l = io.read()
    local func = assert(loadstring("return " .. l))
    print("the value of your expression is " .. func())
