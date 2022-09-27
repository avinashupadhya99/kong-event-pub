foo = {}
function foo.bar()
return "shit"
end
x='foo.bar'
y=assert(loadstring('return '..x..'(...)'))()
print(y)

