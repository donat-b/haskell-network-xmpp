-- Copyright (C) 2010 John Millikin <jmillikin@gmail.com>
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

{-# LANGUAGE OverloadedStrings #-}
module Network.Protocol.XMPP.XML
	( module Data.XML.Types
	, elementChildren
	, hasName
	, getattr
	, getText
	, name
	, nsname
	, element
	, nselement
	, escape
	, serialiseElement
	, readEvents
	, SAX.eventsToElement
	) where
import qualified Data.Text.Lazy as T
import Data.XML.Types
import qualified Text.XML.LibXML.SAX as SAX

elementChildren :: Element -> [Element]
elementChildren = concatMap isElement . elementNodes

hasName :: Name -> Element -> [Element]
hasName n e = [e | elementName e == n]

isElement :: Node -> [Element]
isElement (NodeElement e) = [e]
isElement _ = []

getattr :: Name -> Element -> Maybe T.Text
getattr attrname elemt = case filter ((attrname ==) . attributeName) $ elementAttributes elemt of
	[] -> Nothing
	attr:_ -> Just $ attributeValue attr

getText :: Node -> [T.Text]
getText (NodeText t) = [t]
getText _ = []

name :: T.Text -> Name
name t = Name t Nothing Nothing

nsname :: T.Text -> T.Text -> Name
nsname ns n = Name n (Just ns) Nothing

escape :: T.Text -> T.Text
escape = T.concatMap escapeChar where
	escapeChar c = case c of
		'&' -> "&amp;"
		'<' -> "&lt;"
		'>' -> "&gt;"
		'"' -> "&quot;"
		'\'' -> "&apos;"
		_ -> T.singleton c

element :: T.Text -> [(T.Text, T.Text)] -> [Node] -> Element
element elemName attrs children = Element (name elemName) attrs' children where
	attrs' = [Attribute (name n) value | (n, value) <- attrs]

nselement :: T.Text -> T.Text -> [(T.Text, T.Text)] -> [Node] -> Element
nselement ns ln attrs children = Element (nsname ns ln) attrs' children where
	attrs' = [Attribute (name n) value | (n, value) <- attrs]

-- A somewhat primitive serialisation function
--
-- TODO: better namespace / prefix handling
serialiseElement :: Element -> T.Text
serialiseElement e = text where
	text = T.concat ["<", eName, " ", attrs, ">", contents, "</", eName, ">"]
	eName = formatName $ elementName e
	formatName = escape . nameLocalName
	attrs = T.intercalate " " $ map attr $ elementAttributes e ++ nsattr
	attr (Attribute n v) = T.concat [formatName n, "=\"", escape v, "\""]
	nsattr = case nameNamespace $ elementName e of
		Nothing -> []
		Just ns -> [Attribute (name "xmlns") ns]
	contents = T.concat $ map serialiseNode $ elementNodes e
	
	serialiseNode (NodeElement e') = serialiseElement e'
	serialiseNode (NodeText t) = escape t
	serialiseNode (NodeComment _) = ""
	serialiseNode (NodeInstruction _) = ""

readEvents :: Monad m
           => (Integer -> SAX.Event -> Bool)
           -> m [SAX.Event]
           -> m [SAX.Event]
readEvents done nextEvents = readEvents' 0 [] where
	readEvents' depth acc = do
		events <- nextEvents
		let (done', depth', acc') = step events depth acc
		if done'
			then return acc'
			else readEvents' depth' acc'
	
	step [] depth acc = (False, depth, acc)
	step (e:es) depth acc = let
		depth' = depth + case e of
			(SAX.BeginElement _ _) -> 1
			(SAX.EndElement _) -> (- 1)
			_ -> 0
		acc' = e : acc
		in if done depth' e
			then (True, depth', reverse acc')
			else step es depth' acc'
